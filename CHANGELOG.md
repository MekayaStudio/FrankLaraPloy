# Changelog

All notable changes to FrankenPHP Multi-App Deployer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2025-07-21

### Added
- Complete modular architecture with separated libraries
- FrankenPHP integration for modern PHP deployment
- Laravel Octane support with multiple modes
- HTTP/HTTPS dual mode configuration
- Automatic SSL certificate management via Let's Encrypt
- Comprehensive systemd service management
- Database management tools (MySQL)
- Queue worker and scheduler management
- Multi-app resource monitoring
- Debug and troubleshooting tools
- Extensive command-line interface
- Production optimization features
- Comprehensive documentation with Mermaid diagrams

### Features
- **System Commands**: setup, debug
- **App Management**: install, remove, list, resources, status, logs
- **Service Management**: systemd commands for service control
- **Database Management**: db commands for database operations
- **Octane Management**: octane commands for Laravel Octane control
- **Dual Mode Support**: HTTP/HTTPS configuration options
- **SSL Management**: automatic certificate management
- **Testing Suite**: comprehensive command validation

### Technical Details
- PHP 8.3+ support
- Node.js 18+ integration
- FrankenPHP embedded web server
- HTTP/2 and HTTP/3 support
- Built-in PHP runtime (no PHP-FPM needed)
- Automatic HTTPS with Let's Encrypt
- Systemd service integration
- Multi-app deployment capability

### Documentation
- Complete README.md with usage examples
- Architecture diagrams using Mermaid.js
- Workflow diagrams for system processes
- Quick start guide
- Comprehensive command reference
- Troubleshooting guide
- Testing documentation

### Security
- Automatic HTTPS enforcement options
- Let's Encrypt SSL certificates
- Security validation and setup
- Safe multi-app isolation

### Performance
- Laravel Octane integration
- FrankenPHP performance optimizations
- Resource monitoring and management
- Production-ready configurations

---

## Development Notes

### Code Structure
```
install.sh              # Main script
lib/
  core/
    app-management.sh   # Core app management functions
    laravel-manager.sh  # Laravel-specific management
  modules/
    connection-manager.sh # Connection management
    database-manager.sh   # Database operations
    octane-manager.sh     # Octane management
    ssl-manager.sh        # SSL certificate management
    systemd-manager.sh    # Systemd service management
  utils/
    debug-manager.sh      # Debug and troubleshooting
    error-handler.sh      # Error handling
    security.sh           # Security functions
    shared-functions.sh   # Shared utilities
    system-setup.sh       # System setup functions
    validation.sh         # Input validation
config/
  frankenphp-config.conf # FrankenPHP configuration
```

### Testing
- Command validation script: `validate-commands.sh`
- Comprehensive test suite: `test-commands.sh`
- Manual testing procedures documented
- CI/CD ready structure

### Future Roadmap
- [ ] Docker support
- [ ] Multi-server deployment
- [ ] Load balancer integration
- [ ] Monitoring dashboard
- [ ] Backup automation
- [ ] Database cluster support
