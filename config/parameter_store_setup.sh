#!/usr/bin/env bash
# ==============================================================================
# Script: parameter_store_setup.sh
# Finalidade: Configuração e registro de parâmetros de conexão do Amazon RDS
#             no AWS Systems Manager (SSM) Parameter Store com criptografia KMS.
# Autor: Cesar Lana (Laboratório AWS)
# ==============================================================================

set -euo pipefail

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1"; }
log_error() { echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S')${NC} $1" >&2; }

# Parâmetros padrão
PREFIX="/app/database"
AWS_REGION="${AWS_REGION:-us-east-1}"
KMS_KEY_ID="alias/aws/ssm"

ACTION="put"
ENDPOINT=""
PORT="3306"
DBNAME="ecommerce_db"
DBUSER="admin"
DBPASS=""

show_help() {
    cat << EOF
Uso: $0 [AÇÃO] [OPÇÕES]

Ações:
  --put        Registra ou atualiza os parâmetros no Parameter Store (Padrão)
  --get        Consulta e exibe os parâmetros cadastrados
  --delete     Remove todos os parâmetros cadastrados (Teardown)

Opções para --put:
  -e, --endpoint ENDPOINT  Endpoint do banco RDS
  -P, --port PORT          Porta do banco (padrão: 3306)
  -d, --database NAME      Nome da base de dados (padrão: ecommerce_db)
  -u, --user USER          Nome de usuário (padrão: admin)
  -p, --password PASS      Senha da base (armazenada como SecureString)
  -r, --region REGION      Região AWS (padrão: us-east-1)
  --kms-key KEY_ID         KMS Key ID / Alias (padrão: alias/aws/ssm)
  --help                   Exibe esta ajuda
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --put) ACTION="put"; shift ;;
        --get) ACTION="get"; shift ;;
        --delete) ACTION="delete"; shift ;;
        -e|--endpoint) ENDPOINT="$2"; shift 2 ;;
        -P|--port) PORT="$2"; shift 2 ;;
        -d|--database) DBNAME="$2"; shift 2 ;;
        -u|--user) DBUSER="$2"; shift 2 ;;
        -p|--password) DBPASS="$2"; shift 2 ;;
        -r|--region) AWS_REGION="$2"; shift 2 ;;
        --kms-key) KMS_KEY_ID="$2"; shift 2 ;;
        --help) show_help; exit 0 ;;
        *) log_error "Parâmetro desconhecido: $1"; show_help; exit 1 ;;
    esac
done

if ! command -v aws &> /dev/null; then
    log_error "AWS CLI não encontrado. Por favor, instale o AWS CLI v2."
    exit 1
fi

case "$ACTION" in
    put)
        if [[ -z "$ENDPOINT" || -z "$DBPASS" ]]; then
            log_error "Parâmetros obrigatórios ausentes: --endpoint e --password são exigidos para cadastro."
            show_help
            exit 1
        fi

        log_info "Configurando parâmetros no AWS SSM Parameter Store (${AWS_REGION})..."

        # 1. Endpoint (String)
        aws ssm put-parameter \
            --name "${PREFIX}/endpoint" \
            --value "$ENDPOINT" \
            --type "String" \
            --description "Endpoint de conexao com Amazon RDS MariaDB" \
            --overwrite \
            --region "$AWS_REGION" > /dev/null
        log_success "Registrado: ${PREFIX}/endpoint"

        # 2. Port (String)
        aws ssm put-parameter \
            --name "${PREFIX}/port" \
            --value "$PORT" \
            --type "String" \
            --description "Porta de conexao com Amazon RDS" \
            --overwrite \
            --region "$AWS_REGION" > /dev/null
        log_success "Registrado: ${PREFIX}/port"

        # 3. Database Name (String)
        aws ssm put-parameter \
            --name "${PREFIX}/name" \
            --value "$DBNAME" \
            --type "String" \
            --description "Nome da base de dados padrao da aplicacao" \
            --overwrite \
            --region "$AWS_REGION" > /dev/null
        log_success "Registrado: ${PREFIX}/name"

        # 4. Database User (SecureString)
        aws ssm put-parameter \
            --name "${PREFIX}/user" \
            --value "$DBUSER" \
            --type "SecureString" \
            --key-id "$KMS_KEY_ID" \
            --description "Usuario master da base de dados RDS" \
            --overwrite \
            --region "$AWS_REGION" > /dev/null
        log_success "Registrado: ${PREFIX}/user (SecureString)"

        # 5. Database Password (SecureString)
        aws ssm put-parameter \
            --name "${PREFIX}/password" \
            --value "$DBPASS" \
            --type "SecureString" \
            --key-id "$KMS_KEY_ID" \
            --description "Senha de acesso ao RDS criptografada via KMS" \
            --overwrite \
            --region "$AWS_REGION" > /dev/null
        log_success "Registrado: ${PREFIX}/password (SecureString)"

        log_success "Todos os parâmetros foram armazenados no Parameter Store com sucesso!"
        ;;

    get)
        log_info "Consultando parâmetros sob o caminho ${PREFIX}/ na região ${AWS_REGION}..."
        aws ssm get-parameters-by-path \
            --path "${PREFIX}" \
            --with-decryption \
            --region "$AWS_REGION" \
            --query "Parameters[*].{Name:Name,Type:Type,Value:Value}" \
            --output table
        ;;

    delete)
        log_warn "Removendo parâmetros cadastrados em ${PREFIX}/..."
        for param in endpoint port name user password; do
            PARAM_NAME="${PREFIX}/${param}"
            if aws ssm delete-parameter --name "$PARAM_NAME" --region "$AWS_REGION" 2>/dev/null; then
                log_success "Removido: $PARAM_NAME"
            else
                log_warn "Parâmetro não encontrado: $PARAM_NAME"
            fi
        done
        log_success "Limpeza do Parameter Store concluída!"
        ;;
esac
