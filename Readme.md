# Book API MCP Bundle

This bundle provides a complete Docker Compose setup for running the Book API and its MCP (Model Context Protocol) server, along with all required infrastructure.

## Overview

The `docker-compose.yml` file orchestrates four services that work together to provide a complete Book API ecosystem:

1. **TimescaleDB** - A PostgreSQL database with TimescaleDB extension for data storage
2. **pgAdmin** - Web-based database administration tool
3. **BookApi** - The main ASP.NET Core REST API for managing books
4. **bookapi-mcp-server** - MCP server that exposes the Book API to Claude Desktop

## Services

### TimescaleDB

A PostgreSQL database with TimescaleDB extension running on PostgreSQL 17.

- **Image**: `timescale/timescaledb-ha:pg17`
- **Database**: `propertydb` (note: the BookApi connects to `bookapi` database)
- **User**: `admin`
- **Password**: Empty (no password set)
- **Health Check**: Monitors database readiness every 10 seconds
- **Data Persistence**: Uses a Docker volume (`postgres-data`) to persist data

### pgAdmin

Web-based PostgreSQL administration interface for managing the database.

- **Image**: `dpage/pgadmin4`
- **Access**: http://localhost:5050
- **Email**: `admin@admin.com`
- **Password**: Empty (no password set)
- **Dependencies**: Waits for TimescaleDB to be ready

Use pgAdmin to:
- Run the `books-data.sql` script to set up the database schema
- Create the `bookapi` database
- Manage and query the books data

### BookApi

The main REST API service built from the `../BookApi` directory.

- **Build Context**: `../BookApi`
- **Environment**: Development
- **Connection String**: Connects to TimescaleDB at `timescaledb:5432` using the `bookapi` database
- **Dependencies**: Waits for TimescaleDB to be ready

The API provides endpoints for managing books (CRUD operations).

### bookapi-mcp-server

MCP server that bridges Claude Desktop with the Book API.

- **Build Context**: `../book-api-mcp-server-dotnet`
- **Environment**: Configures the Book API base URL to `http://bookapi:8080`
- **Dependencies**: Waits for BookApi to be ready

This service exposes the Book API functionality through the Model Context Protocol, allowing Claude Desktop to interact with the book database.

## Usage

### Starting the Services

```bash
docker-compose up -d
```

This will start all services in detached mode. The services will start in dependency order:
1. TimescaleDB first
2. pgAdmin (waits for TimescaleDB)
3. BookApi (waits for TimescaleDB)
4. bookapi-mcp-server (waits for BookApi)

### Setting Up the Database

1. Access pgAdmin at http://localhost:5050
2. Login with `admin@admin.com` (no password)
3. Add a new server connection:
   - Host: `timescaledb`
   - Port: `5432`
   - Database: `propertydb` (initial connection)
   - Username: `admin`
   - Password: (leave empty)
4. Create the `bookapi` database (or use the SQL script)
5. Run the `books-data.sql` script in the `bookapi` database to create the schema and sample data

### Stopping the Services

```bash
docker-compose down
```

To also remove volumes (⚠️ **this will delete all data**):

```bash
docker-compose down -v
```

### Viewing Logs

View logs for all services:
```bash
docker-compose logs -f
```

View logs for a specific service:
```bash
docker-compose logs -f bookapi
```

## Configuration

### Environment Variables

- **TimescaleDB**: Uses default PostgreSQL environment variables
- **BookApi**: Connection string is configured via `ConnectionStrings__DefaultConnection`
- **bookapi-mcp-server**: Book API URL is configured via `BookApi__BaseUrl`

### Volumes

Two named volumes are created:
- `postgres-data`: Stores TimescaleDB data (persists across container restarts)
- `pgadmin_data`: Stores pgAdmin configuration and settings

## Network

All services run on the default Docker Compose network, allowing them to communicate using their service names as hostnames (e.g., `timescaledb`, `bookapi`).

## Notes

- The database password is empty by default. For production use, set secure passwords in the environment variables.
- The BookApi service connects to a database named `bookapi`, but TimescaleDB initializes with `propertydb`. You'll need to create the `bookapi` database manually or via the SQL script.
- The pgAdmin interface is accessible on port `5050` on your host machine.

