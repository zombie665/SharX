# 3X-UI New

[English](README_EN.md) | [Русский](README_RU.md)

## Welcome to the New 3x-ui / Добро пожаловать в новую 3x-ui

Welcome to the next generation of 3x-ui! This version brings significant improvements, a modern architecture, and a streamlined installation process using Docker containers.

Добро пожаловать в новое поколение 3x-ui! Эта версия приносит значительные улучшения, современную архитектуру и упрощенный процесс установки с использованием Docker-контейнеров.

## Quick Start / Быстрый старт

### Panel Installation / Установка панели

1. Clone the repository:
   ```bash
   git clone https://github.com/konstpic/3x-ui-new.git
   cd 3x-ui-new
   ```

2. Configure `docker-compose.yml`:
   - Change database passwords
   - Adjust ports if needed
   - Prepare SSL certificates in `cert/` directory

3. Start services:
   ```bash
   docker-compose up -d
   ```

4. Access the panel at `http://your-server-ip:2053`

### Node Installation / Установка узла

1. Navigate to node directory:
   ```bash
   cd node
   ```

2. Configure `docker-compose.yml` and prepare certificates

3. Start the node:
   ```bash
   docker-compose up -d
   ```

## Key Features / Основные возможности

- **Node Mode**: One panel manages multiple nodes
- **PostgreSQL**: Full migration from SQLite
- **Redis Integration**: Enhanced performance with caching
- **Modern UI**: Glass Morphism design
- **Docker-Based**: Easy deployment with pre-built images
- **HWID Protection**: Device identification (Beta, Happ & V2RayTun)

- **Режим узлов**: Одна панель управляет несколькими узлами
- **PostgreSQL**: Полная миграция с SQLite
- **Интеграция Redis**: Повышенная производительность с кэшированием
- **Современный интерфейс**: Дизайн Glass Morphism
- **На основе Docker**: Легкое развертывание с предварительно собранными образами
- **Защита HWID**: Идентификация устройств (Бета, Happ & V2RayTun)

## Documentation / Документация

For detailed installation instructions, configuration, and migration guide, please see:

Для подробных инструкций по установке, настройке и миграции, пожалуйста, смотрите:

- **[Full English Documentation](README_EN.md)** - Complete guide in English
- **[Полная русская документация](README_RU.md)** - Полное руководство на русском языке

## Requirements / Требования

- Docker and Docker Compose
- Domain name (for TLS)
- SSL certificates (for HTTPS)

- Docker и Docker Compose
- Доменное имя (для TLS)
- SSL-сертификаты (для HTTPS)

## Support / Поддержка

For issues, questions, or contributions, please refer to the project repository.

По вопросам, проблемам или вкладу в проект обращайтесь в репозиторий проекта.

---

**Note**: This version uses Docker containers for easy deployment. All images are pre-built and ready to use.

**Примечание**: Эта версия использует Docker-контейнеры для легкого развертывания. Все образы предварительно собраны и готовы к использованию.
