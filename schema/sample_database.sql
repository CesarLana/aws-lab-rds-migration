-- ==============================================================================
-- Schema de Exemplo: ecommerce_db
-- Usado no laboratório de migração EC2 (MariaDB) -> Amazon RDS (MariaDB/MySQL)
-- ==============================================================================

CREATE DATABASE IF NOT EXISTS `ecommerce_db` 
  CHARACTER SET utf8mb4 
  COLLATE utf8mb4_unicode_ci;

USE `ecommerce_db`;

-- Desativar verificação de chaves estrangeiras temporariamente
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `order_items`;
DROP TABLE IF EXISTS `orders`;
DROP TABLE IF EXISTS `products`;
DROP TABLE IF EXISTS `categories`;
DROP TABLE IF EXISTS `customers`;

-- 1. Tabela de Clientes
CREATE TABLE `customers` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `first_name` VARCHAR(50) NOT NULL,
  `last_name` VARCHAR(50) NOT NULL,
  `email` VARCHAR(100) NOT NULL UNIQUE,
  `cpf` VARCHAR(14) NOT NULL UNIQUE,
  `phone` VARCHAR(20) DEFAULT NULL,
  `city` VARCHAR(50) NOT NULL,
  `state` VARCHAR(2) NOT NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_customers_email` (`email`),
  INDEX `idx_customers_state` (`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Tabela de Categorias
CREATE TABLE `categories` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(50) NOT NULL UNIQUE,
  `description` TEXT,
  `active` BOOLEAN DEFAULT TRUE,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Tabela de Produtos
CREATE TABLE `products` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `category_id` INT NOT NULL,
  `sku` VARCHAR(30) NOT NULL UNIQUE,
  `name` VARCHAR(150) NOT NULL,
  `price` DECIMAL(10,2) NOT NULL,
  `stock_quantity` INT NOT NULL DEFAULT 0,
  `status` ENUM('AVAILABLE', 'OUT_OF_STOCK', 'DISCONTINUED') DEFAULT 'AVAILABLE',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`) ON DELETE RESTRICT,
  INDEX `idx_products_sku` (`sku`),
  INDEX `idx_products_category` (`category_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. Tabela de Pedidos
CREATE TABLE `orders` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `customer_id` INT NOT NULL,
  `order_number` VARCHAR(36) NOT NULL UNIQUE,
  `status` ENUM('PENDING', 'PROCESSING', 'SHIPPED', 'DELIVERED', 'CANCELLED') DEFAULT 'PENDING',
  `total_amount` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `shipping_cost` DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`) ON DELETE RESTRICT,
  INDEX `idx_orders_customer` (`customer_id`),
  INDEX `idx_orders_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. Tabela de Itens de Pedidos
CREATE TABLE `order_items` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `order_id` INT NOT NULL,
  `product_id` INT NOT NULL,
  `quantity` INT NOT NULL,
  `unit_price` DECIMAL(10,2) NOT NULL,
  `subtotal` DECIMAL(10,2) GENERATED ALWAYS AS (`quantity` * `unit_price`) STORED,
  FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`product_id`) REFERENCES `products` (`id`) ON DELETE RESTRICT,
  INDEX `idx_order_items_order` (`order_id`),
  INDEX `idx_order_items_product` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Reativar verificação de chaves estrangeiras
SET FOREIGN_KEY_CHECKS = 1;

-- ==============================================================================
-- Carga Inicial de Dados de Teste
-- ==============================================================================

-- Categorias
INSERT INTO `categories` (`name`, `description`) VALUES
('Servidores e Cloud', 'Infraestrutura computacional, instâncias e hardware virtualizado'),
('Redes e Segurança', 'Appliances de firewall, switches, roteadores e balanceadores de carga'),
('Armazenamento', 'Discos NVMe, gavetas SAN/NAS e fitas de backup'),
('Banco de Dados', 'Softwares corporativos, conectores e ferramentas de replicação'),
('Desenvolvimento', 'Acessórios, periféricos e estações de engenharia');

-- Clientes
INSERT INTO `customers` (`first_name`, `last_name`, `email`, `cpf`, `phone`, `city`, `state`) VALUES
('Carlos', 'Eduardo', 'carlos.eduardo@empresa.com.br', '111.222.333-44', '+55 11 98765-4321', 'São Paulo', 'SP'),
('Mariana', 'Silva', 'mariana.silva@techcorp.io', '222.333.444-55', '+55 21 97654-3210', 'Rio de Janeiro', 'RJ'),
('Rafael', 'Menezes', 'rafael.menezes@fintech.com', '333.444.555-66', '+55 31 96543-2109', 'Belo Horizonte', 'MG'),
('Beatriz', 'Costa', 'beatriz.costa@startup.ai', '444.555.666-77', '+55 41 95432-1098', 'Curitiba', 'PR'),
('Lucas', 'Almeida', 'lucas.almeida@cloudsys.net', '555.666.777-88', '+55 51 94321-0987', 'Porto Alegre', 'RS');

-- Produtos
INSERT INTO `products` (`category_id`, `sku`, `name`, `price`, `stock_quantity`, `status`) VALUES
(1, 'SRV-DL380-G10', 'Servidor HP ProLiant DL380 Gen10 Xeon 128GB', 28500.00, 4, 'AVAILABLE'),
(1, 'SRV-R740-XEON', 'Servidor Dell PowerEdge R740 64GB ECC', 22900.00, 6, 'AVAILABLE'),
(2, 'NET-FG-100F', 'Fortinet FortiGate 100F Next-Gen Firewall', 15400.00, 10, 'AVAILABLE'),
(2, 'NET-C9200-48P', 'Switch Cisco Catalyst 9200L 48 Portas PoE+', 18900.00, 5, 'AVAILABLE'),
(3, 'STR-NVME-768T', 'SSD Enterprise U.2 NVMe 7.68TB Read-Intensive', 4800.00, 25, 'AVAILABLE'),
(3, 'STR-NAS-8BAY', 'Storage NAS QNAP Enterprise 8-Bay 10GbE', 12300.00, 3, 'AVAILABLE'),
(4, 'SFT-DB-ORCL19', 'Licença Enterprise Database Standard Unit', 9500.00, 15, 'AVAILABLE'),
(5, 'ACC-KBD-MECH', 'Teclado Mecânico Ergonômico de Engenharia', 750.00, 50, 'AVAILABLE');

-- Pedidos
INSERT INTO `orders` (`customer_id`, `order_number`, `status`, `total_amount`, `shipping_cost`) VALUES
(1, 'ORD-2026-0001', 'DELIVERED', 51400.00, 250.00),
(2, 'ORD-2026-0002', 'PROCESSING', 15400.00, 120.00),
(3, 'ORD-2026-0003', 'SHIPPED', 23650.00, 180.00),
(4, 'ORD-2026-0004', 'PENDING', 4800.00, 80.00),
(5, 'ORD-2026-0005', 'DELIVERED', 31200.00, 310.00);

-- Itens de Pedido
INSERT INTO `order_items` (`order_id`, `product_id`, `quantity`, `unit_price`) VALUES
(1, 1, 1, 28500.00),
(1, 2, 1, 22900.00),
(2, 3, 1, 15400.00),
(3, 2, 1, 22900.00),
(3, 8, 1, 750.00),
(4, 5, 1, 4800.00),
(5, 1, 1, 28500.00),
(5, 5, 1, 4800.00);

-- Trigger de Auditoria para Atualização de Status
DELIMITER $$
CREATE TRIGGER `trg_after_order_update`
AFTER UPDATE ON `orders`
FOR EACH ROW
BEGIN
  IF OLD.status != NEW.status THEN
    INSERT INTO `categories` (`name`, `description`) 
    VALUES (CONCAT('Audit_', NEW.order_number, '_', UNIX_TIMESTAMP()), 
            CONCAT('Status mudou de ', OLD.status, ' para ', NEW.status))
    ON DUPLICATE KEY UPDATE `description` = VALUES(`description`);
  END IF;
END$$
DELIMITER ;
