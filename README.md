# FrankLaraPloy

🚀 **FrankenPHP Multi-App Deployer for Laravel Applications**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-24.04%20LTS-orange.svg)](https://ubuntu.com/)
[![PHP](https://img.shields.io/badge/PHP-8.3+-blue.svg)](https://php.net/)
[![Laravel](https://img.shields.io/badge/Laravel-10%2B-red.svg)](https://laravel.com/)

Script deployment otomatis untuk aplikasi Laravel menggunakan FrankenPHP dengan arsitektur modular yang dioptimasi untuk Indonesia.

## ✨ Features

- **🏗️ Modular Architecture** - Code terorganisir dalam modul terpisah
- **🇮🇩 Indonesia Mirror** - Mirror Ubuntu Indonesia untuk download cepat
- **📊 Resource Awareness** - Monitoring dan optimasi resource otomatis
- **⚡ Command Shortcuts** - Perintah mudah tanpa path panjang
- **🔒 Auto HTTPS** - SSL otomatis dengan Let's Encrypt
- **🔄 GitHub Integration** - Deploy otomatis dari repository
- **🛡️ Auto Rollback** - Rollback otomatis jika terjadi error

## 🚀 Quick Start

### Prerequisites

- Ubuntu 24.04 LTS
- Root access
- Internet connection

### Installation

```bash
# Clone repository
git clone https://github.com/MekayaStudio/FrankLaraPloy.git
cd FrankLaraPloy

# Install
sudo ./install.sh

# Setup system
sudo frankenphp-setup
```

### Basic Usage

```bash
# Create Laravel app
create-laravel-app myapp domain.com https://github.com/user/repo.git

# Deploy app
deploy-laravel-app myapp

# Monitor resources
monitor-server-resources
```

## 📚 Commands

### App Management
```bash
create-laravel-app <name> <domain> [repo]    # Create new app
deploy-laravel-app <name>                     # Deploy app
list-laravel-apps                             # List all apps
status-laravel-app <name>                     # Check app status
remove-laravel-app <name>                     # Remove app
```

### Monitoring
```bash
monitor-server-resources                      # Monitor server resources
analyze-app-resources                         # Analyze app resources
backup-all-laravel-apps                       # Backup all apps
```

### System
```bash
frankenphp-setup                              # Setup system
frankenphp help                               # Show help
```

## 🏗️ Architecture

```
FrankLaraPloy/
├── frankenphp-multiapp-deployer-optimized.sh  # Main script
├── install.sh                                 # Installer
├── lib/                                        # Modules
│   ├── config.sh                              # Configuration
│   ├── utils.sh                               # Utilities
│   ├── system_setup.sh                        # System setup
│   ├── resource_management.sh                 # Resource monitoring
│   └── app_management.sh                      # App management
├── README.md                                  # Documentation
└── SUMMARY.md                                 # Summary
```

## ⚙️ Configuration

### Indonesia Mirrors
- **Primary**: mirror.unpad.ac.id (UNPAD)
- **Secondary**: mirror.unej.ac.id (UNEJ)
- **Tertiary**: mirror.repository.id

### Resource Limits
- Memory safety margin: 20%
- CPU safety margin: 25%
- Min memory per app: 512MB
- Max apps per server: 10

## 📝 App Naming Rules

### ✅ Valid Names
- `web_sam_l12`
- `api_service_v2`
- `websaml12`

### ❌ Invalid Names
- `web-sam-l12` (dashes not allowed)
- `123web` (cannot start with number)
- `web sam` (spaces not allowed)

## 🔧 Examples

### Create App from GitHub
```bash
create-laravel-app web_sam testingsetup.rizqis.com https://github.com/CompleteLabs/web-app-sam.git
```

### Create Empty App
```bash
create-laravel-app api_service api.domain.com
```

### Deploy and Monitor
```bash
deploy-laravel-app web_sam
status-laravel-app web_sam
monitor-server-resources
```

## 🛠️ Troubleshooting

### Command Not Found
```bash
sudo ./install.sh
```

### Slow Downloads
System automatically falls back to alternative mirrors.

### Resource Issues
```bash
monitor-server-resources
remove-laravel-app unused_app
```

## 📊 Performance

- **5-10x faster** downloads with Indonesia mirrors
- **Modular architecture** for better maintainability
- **Smart resource allocation** based on server capacity
- **Zero-downtime deployment**

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- FrankenPHP team for the amazing server
- Laravel community
- Indonesian mirror providers
- All contributors

## 📞 Support

- 🐛 [Issues](https://github.com/MekayaStudio/FrankLaraPloy/issues)
- 💬 [Discussions](https://github.com/MekayaStudio/FrankLaraPloy/discussions)
- 📧 Email: support@mekayastudio.com

---

**Made with ❤️ for Indonesian Laravel Developers**
