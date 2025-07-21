# 🚀 FrankenPHP Quick Start Guide

Panduan cepat untuk memulai dengan FrankenPHP Multi-App Deployer.

## Step 1: Setup System

```bash
# Clone repository
git clone https://github.com/MekayaStudio/FrankLaraPloy.git
cd FrankLaraPloy

# Make script executable
chmod +x install.sh

# Setup system (install FrankenPHP, MySQL, Redis, etc.)
sudo ./install.sh setup
```

## Step 2: Deploy First App

```bash
# Basic deployment
sudo ./install.sh install myapp mydomain.com

# With specific repository
sudo ./install.sh install blog myblog.com https://github.com/user/laravel-blog.git

# Production mode with HTTPS only
sudo ./install.sh install shop myshop.com "" "" smart https-only
```

## Step 3: Manage Apps

```bash
# Check app status
sudo ./install.sh status myapp

# View logs
sudo ./install.sh logs myapp 50

# List all apps
sudo ./install.sh list

# Check resources
sudo ./install.sh resources
```

## Step 4: Configure Services

```bash
# Configure dual mode (HTTP + HTTPS)
sudo ./install.sh octane:dual myapp dual

# Start dual mode services
sudo ./install.sh octane:start-dual myapp dual

# Check service status
sudo ./install.sh octane:status-dual myapp dual
```

## Troubleshooting

```bash
# Debug system
sudo ./install.sh debug

# Debug specific app
sudo ./install.sh debug myapp

# Fix all services
sudo ./install.sh systemd:fix-all

# Check database
sudo ./install.sh db:status
sudo ./install.sh db:list
```

## Validation

```bash
# Quick test all commands
bash validate-commands.sh

# Comprehensive testing
bash test-commands.sh
```

## Next Steps

- Read full [README.md](README.md) for detailed documentation
- Check [architecture diagrams](README.md#-architecture)
- Explore [advanced usage](README.md#-advanced-usage)
- Review [troubleshooting](README.md#-troubleshooting)

---

**Happy deploying with FrankenPHP! 🎉**
