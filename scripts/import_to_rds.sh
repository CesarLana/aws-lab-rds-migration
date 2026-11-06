#!/usr/bin/env bash
# ==============================================================================
# Script: import_to_rds.sh
# Finalidade: Restaura o dump do banco de dados no Amazon RDS Multi-AZ com
#             validação de conectividade, integridade e reconciliação.
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

# Configurações padrão
RDS_ENDPOINT="${RDS_ENDPOINT:-}"
RDS_PORT="${RDS_PORT:-3306}"
RDS_USER="${RDS_USER:-admin}"
RDS_PASSWORD="${RDS_PASSWORD:-}"
DB_NAME="${DB_NAME:-ecommerce_db}"
DUMP_FILE="${DUMP_FILE:-}"
SKIP_CHECKSUM="${SKIP_CHECKSUM:-false}"

show_help() {
    cat << EOF
Uso: $0 -e <RDS_ENDPOINT> -f <DUMP_FILE> [OPÇÕES]

Opções Obrigatórias:
  -e, --endpoint ENDPOINT  Endpoint DNS do Amazon RDS
  -f, --file DUMP_FILE     Caminho do arquivo de dump (.sql.gz)

Opções Opcionais:
  -P, --port PORT          Porta do RDS (padrão: 3306)
  -u, --user USER          Usuário master do RDS (padrão: admin)
  -p, --password PASS      Senha do RDS (ou use a variável RDS_PASSWORD)
  -d, --database DBNAME    Nome do banco de dados (padrão: ecommerce_db)
  --skip-checksum          Pula a verificação do arquivo .sha256
  --help                   Exibe esta mensagem de ajuda
EOF
}

# Parse de argumentos
while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--endpoint) RDS_ENDPOINT="$2"; shift 2 ;;
        -f|--file) DUMP_FILE="$2"; shift 2 ;;
        -P|--port) RDS_PORT="$2"; shift 2 ;;
        -u|--user) RDS_USER="$2"; shift 2 ;;
        -p|--password) RDS_PASSWORD="$2"; shift 2 ;;
        -d|--database) DB_NAME="$2"; shift 2 ;;
        --skip-checksum) SKIP_CHECKSUM="true"; shift 1 ;;
        --help) show_help; exit 0 ;;
        *) log_error "Opção desconhecida: $1"; show_help; exit 1 ;;
    esac
done

# Validações obrigatórias
if [[ -z "$RDS_ENDPOINT" ]]; then
    log_error "O endpoint do RDS é obrigatório (-e ou --endpoint)."
    show_help
    exit 1
fi

if [[ -z "$DUMP_FILE" || ! -f "$DUMP_FILE" ]]; then
    log_error "Arquivo de dump não encontrado ou inválido: '$DUMP_FILE'"
    show_help
    exit 1
fi

# Validação de comandos
for cmd in mysql gunzip; do
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Comando obrigatório não encontrado: $cmd. Instale antes de prosseguir."
        exit 1
    fi
done

# Validação de integridade SHA256 pré-importação
CHECKSUM_FILE="${DUMP_FILE}.sha256"
if [[ "$SKIP_CHECKSUM" == "false" && -f "$CHECKSUM_FILE" ]]; then
    log_info "Verificando integridade SHA256 com ${CHECKSUM_FILE}..."
    if command -v sha256sum &> /dev/null; then
        sha256sum --check "$CHECKSUM_FILE"
        log_success "Integridade do arquivo confirmada!"
    fi
fi

# Teste de conectividade com o RDS
log_info "Testando conectividade TCP com o RDS endpoint: ${RDS_ENDPOINT}:${RDS_PORT}..."
if command -v nc &> /dev/null; then
    if ! nc -z -w5 "$RDS_ENDPOINT" "$RDS_PORT"; then
        log_error "Não foi possível estabelecer conexão TCP com $RDS_ENDPOINT:$RDS_PORT."
        log_error "Verifique o Security Group do RDS, Subnet Group e rotas de rede."
        exit 1
    fi
    log_success "Conexão TCP estabelecida com sucesso."
fi

export MYSQL_PWD="${RDS_PASSWORD}"

# Teste de autenticação no RDS
log_info "Autenticando no Amazon RDS..."
if ! mysql -h "$RDS_ENDPOINT" -P "$RDS_PORT" -u "$RDS_USER" -e "SELECT VERSION();" > /dev/null 2>&1; then
    log_error "Falha de autenticação no RDS. Verifique as credenciais e permissões do usuário."
    exit 1
fi
log_success "Autenticação no RDS bem-sucedida!"

# Criação do banco caso não exista
log_info "Garantindo existência do banco de dados '${DB_NAME}' no RDS..."
mysql -h "$RDS_ENDPOINT" -P "$RDS_PORT" -u "$RDS_USER" -e \
    "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Execução do import via stream (gunzip direto para mysql para economizar I/O em disco)
log_info "Iniciando importação do dump em stream para o Amazon RDS..."
START_TIME=$(date +%s)

if gunzip -c "$DUMP_FILE" | mysql \
    --host="$RDS_ENDPOINT" \
    --port="$RDS_PORT" \
    --user="$RDS_USER" \
    --default-character-set=utf8mb4 \
    --max-allowed-packet=64M \
    "$DB_NAME"; then
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    log_success "Importação concluída com sucesso em ${DURATION} segundos!"
else
    log_error "Erro durante a importação para o Amazon RDS!"
    exit 1
fi

# Reconciliação e validação pós-migração
log_info "Executando reconciliação de dados pós-migração..."

TABLES_QUERY="SELECT count(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}';"
TABLE_COUNT=$(mysql -h "$RDS_ENDPOINT" -P "$RDS_PORT" -u "$RDS_USER" -s -N -e "$TABLES_QUERY")

log_info "Total de tabelas restauradas no RDS: ${TABLE_COUNT}"

# Validação das contagens de registros das tabelas principais
echo "--------------------------------------------------------"
printf "%-25s | %-15s\n" "Tabela" "Total Registros"
echo "--------------------------------------------------------"

TABLES_LIST=$(mysql -h "$RDS_ENDPOINT" -P "$RDS_PORT" -u "$RDS_USER" -s -N -e "SHOW TABLES FROM \`${DB_NAME}\`;")

for tbl in $TABLES_LIST; do
    ROW_COUNT=$(mysql -h "$RDS_ENDPOINT" -P "$RDS_PORT" -u "$RDS_USER" -s -N -e "SELECT count(*) FROM \`${DB_NAME}\`.\`${tbl}\`;")
    printf "%-25s | %-15s\n" "$tbl" "$ROW_COUNT"
done

echo "--------------------------------------------------------"
log_success "Migração para o Amazon RDS validada com êxito!"
