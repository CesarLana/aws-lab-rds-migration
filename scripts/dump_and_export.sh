#!/usr/bin/env bash
# ==============================================================================
# Script: dump_and_export.sh
# Finalidade: Executa dump consistente e comprimido do banco MariaDB on-EC2
#             com cálculo de checksum SHA256 e upload opcional para S3.
# Autor: Cesar Lana (Laboratório AWS)
# ==============================================================================

set -euo pipefail

# Cores para formatação de logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1" >&2
}

# Configurações padrão (podem ser sobrescritas por variáveis de ambiente ou flags)
DB_HOST="${DB_HOST:-127.0.0.1}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-root}"
DB_PASSWORD="${DB_PASSWORD:-}"
DB_NAME="${DB_NAME:-ecommerce_db}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/db_migration}"
S3_BUCKET="${S3_BUCKET:-}"

show_help() {
    cat << EOF
Uso: $0 [OPÇÕES]

Opções:
  -h, --host HOST        Endereço do host do banco de dados (padrão: 127.0.0.1)
  -P, --port PORT        Porta do banco de dados (padrão: 3306)
  -u, --user USER        Usuário do banco de dados (padrão: root)
  -p, --password PASS    Senha do banco (ou use a variável DB_PASSWORD)
  -d, --database DBNAME  Nome do banco de dados a exportar (padrão: ecommerce_db)
  -o, --output-dir DIR   Diretório de destino do backup (padrão: /tmp/db_migration)
  -s, --s3-bucket BUCKET Nome do bucket S3 opcional para upload
  --help                 Exibe esta mensagem de ajuda
EOF
}

# Parse de argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--host) DB_HOST="$2"; shift 2 ;;
        -P|--port) DB_PORT="$2"; shift 2 ;;
        -u|--user) DB_USER="$2"; shift 2 ;;
        -p|--password) DB_PASSWORD="$2"; shift 2 ;;
        -d|--database) DB_NAME="$2"; shift 2 ;;
        -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -s|--s3-bucket) S3_BUCKET="$2"; shift 2 ;;
        --help) show_help; exit 0 ;;
        *) log_error "Opção desconhecida: $1"; show_help; exit 1 ;;
    esac
done

# Validação de dependências
for cmd in mysqldump gzip sha256sum; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Comando obrigatório não encontrado: $cmd. Instale antes de prosseguir."
        exit 1
    fi
done

# Criação do diretório de saída
mkdir -p "$OUTPUT_DIR"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DUMP_FILENAME="${DB_NAME}_dump_${TIMESTAMP}.sql.gz"
DUMP_FILEPATH="${OUTPUT_DIR}/${DUMP_FILENAME}"
CHECKSUM_FILE="${DUMP_FILEPATH}.sha256"
METADATA_FILE="${OUTPUT_DIR}/${DB_NAME}_metadata_${TIMESTAMP}.json"

log_info "Iniciando processo de dump para o banco: ${DB_NAME}"
log_info "Origem: ${DB_USER}@${DB_HOST}:${DB_PORT}"
log_info "Destino local: ${DUMP_FILEPATH}"

# Montagem de flags do mysqldump
# Usamos MYSQL_PWD para evitar expor a senha na tabela de processos (ps)
export MYSQL_PWD="${DB_PASSWORD}"

DUMP_CMD=(
    mysqldump
    --host="$DB_HOST"
    --port="$DB_PORT"
    --user="$DB_USER"
    --single-transaction          # Garante consistência em tabelas InnoDB sem travar writes
    --quick                       # Stream de linhas sem cachear tabela inteira na RAM da EC2
    --routines                    # Preserva stored procedures e funções
    --triggers                    # Preserva triggers de banco
    --events                      # Preserva event schedulers
    --set-gtid-purged=OFF         # Evita falha de privilégios de superusuário no Amazon RDS
    --default-character-set=utf8mb4
    --hex-blob                    # Preserva campos binários sem corromper
    --databases "$DB_NAME"
)

START_TIME=$(date +%s)

# Execução do dump com pipe para compressão máxima (gzip -9)
log_info "Executando mysqldump e comprimindo com gzip..."
if "${DUMP_CMD[@]}" | gzip -9 > "$DUMP_FILEPATH"; then
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    FILE_SIZE=$(du -h "$DUMP_FILEPATH" | cut -f1)
    log_success "Dump concluído com sucesso em ${DURATION}s. Tamanho: ${FILE_SIZE}"
else
    log_error "Falha crítica durante a execução do mysqldump!"
    rm -f "$DUMP_FILEPATH"
    exit 1
fi

# Cálculo de integridade SHA256
log_info "Calculando checksum SHA256 para integridade..."
sha256sum "$DUMP_FILEPATH" > "$CHECKSUM_FILE"
HASH_VALUE=$(cut -d' ' -f1 "$CHECKSUM_FILE")
log_success "Checksum SHA256: ${HASH_VALUE}"

# Coleta de metadados de validação
TABLE_COUNT=$(mysql --host="$DB_HOST" --port="$DB_PORT" --user="$DB_USER" -e "SELECT count(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';" -s -N 2>/dev/null || echo "N/A")

cat << EOF > "$METADATA_FILE"
{
  "database": "${DB_NAME}",
  "source_host": "${DB_HOST}",
  "timestamp": "${TIMESTAMP}",
  "file_name": "${DUMP_FILENAME}",
  "file_size": "${FILE_SIZE}",
  "sha256": "${HASH_VALUE}",
  "table_count": ${TABLE_COUNT:-0},
  "duration_seconds": ${DURATION}
}
EOF

log_info "Metadados gerados em: ${METADATA_FILE}"

# Upload opcional para Amazon S3
if [[ -n "$S3_BUCKET" ]]; then
    if ! command -v aws &> /dev/null; then
        log_warn "AWS CLI não encontrado. Ignorando upload para S3."
    else
        log_info "Enviando arquivo para o bucket s3://${S3_BUCKET}/migration/..."
        aws s3 cp "$DUMP_FILEPATH" "s3://${S3_BUCKET}/migration/${DUMP_FILENAME}"
        aws s3 cp "$CHECKSUM_FILE" "s3://${S3_BUCKET}/migration/${DUMP_FILENAME}.sha256"
        aws s3 cp "$METADATA_FILE" "s3://${S3_BUCKET}/migration/${DB_NAME}_metadata_${TIMESTAMP}.json"
        log_success "Upload para o Amazon S3 concluído com sucesso!"
    fi
fi

log_success "Exportação finalizada com sucesso! O arquivo está pronto para importação no RDS."
echo "--------------------------------------------------------"
echo "Arquivo de Dump : $DUMP_FILEPATH"
echo "Checksum SHA256 : $CHECKSUM_FILE"
echo "Metadados JSON  : $METADATA_FILE"
echo "--------------------------------------------------------"
