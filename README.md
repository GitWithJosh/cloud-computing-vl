# Calorie Guesser OpenStack Deployment

This project deploys the Calorie Guesser Python application to OpenStack using Pulumi Infrastructure as Code with comprehensive logging and status monitoring.

## Prerequisites

1. **Pulumi CLI** installed on your machine
2. **Python 3.7+** installed
3. **OpenStack credentials** configured
4. Your **SSH key pair** created in OpenStack (you'll specify the name during deployment)
5. The following files in your project directory:
   - `calo_guessr_v1.py`
   - `calo_guessr_v2.py`
   - `requirements.txt`

## Project Structure

```
.
├── __main__.py                 # Pulumi infrastructure code
├── Pulumi.yaml                # Pulumi project configuration
├── requirements-pulumi.txt    # Pulumi dependencies
├── deploy.sh                  # Deployment script
├── openrc.sh                  # OpenStack environment variables template
├── README.md                  # This file
├── .gitignore                 # Git ignore file
├── calo_guessr_v1.py         # Your Python script v1
├── calo_guessr_v2.py         # Your Python script v2
└── requirements.txt          # Your Python app dependencies
```

## OpenStack Configuration

The deployment uses these OpenStack settings:
- **Image ID**: `c57c2aef-f74a-4418-94ca-d3fb169162bf`
- **Flavor**: `cb1.medium`
- **Key Pair**: User configurable (you specify during deployment)
- **Network**: `provider_912`
- **Security Groups**: `["default"]`

## Setup Instructions

### 1. Configure OpenStack Credentials

#### Option A: Using openrc.sh (Recommended)
1. Customize the OpenStack environment file:
   ```bash
   cp openrc-template.sh openrc.sh
   # Edit openrc.sh with your OpenStack credentials
   ```

2. Source the file:
   ```bash
   source openrc.sh
   ```

#### Option B: Manual Environment Variables
Set up your OpenStack environment variables manually:
```bash
export OS_AUTH_URL=<your-auth-url>
export OS_USERNAME=<your-username>
export OS_PASSWORD=<your-password>
export OS_PROJECT_NAME=<your-project-name>
export OS_USER_DOMAIN_NAME=<your-domain>
export OS_PROJECT_DOMAIN_NAME=<your-domain>
export OS_IDENTITY_API_VERSION=3
```

### 2. Install Dependencies

```bash
pip install -r requirements-pulumi.txt
```

### 3. Deploy the Application

Make the deployment script executable and run it:

```bash
chmod +x deploy.sh

# Deploy with interactive key pair input
./deploy.sh v1
# or
./deploy.sh v2

# Deploy with key pair specified
./deploy.sh v1 my-keypair
./deploy.sh v2 my-keypair
```

## Manual Deployment

If you prefer to deploy manually:

1. **Initialize Pulumi stack:**
   ```bash
   pulumi stack init calo-guessr-v1  # or calo-guessr-v2
   ```

2. **Set configuration:**
   ```bash
   pulumi config set version v1  # or v2
   pulumi config set key_pair your-keypair-name
   ```

3. **Deploy:**
   ```bash
   pulumi up
   ```

## What Gets Deployed

1. **OpenStack Compute Instance** with the specified configuration
2. **Streamlit Python application** installed and configured as a systemd service
3. **Virtual environment** with all dependencies installed
4. **Comprehensive logging system** for deployment and application monitoring
5. **Status monitoring tools** and scripts
6. **Web interface** accessible on port 8501

**Note**: This deployment uses the instance's private IP address. No floating IP is created due to system administrator restrictions.

## Deployment Status Monitoring

The deployment includes comprehensive logging to track the setup process and application readiness:

### Real-time Deployment Monitoring
After deployment, monitor the setup process:
```bash
# Watch setup progress (using private IP)
ssh -i ~/.ssh/your-keypair ubuntu@<private-ip> 'sudo tail -f /var/log/calo-guessr-setup.log'
```

### Application Readiness Indicators
The setup log will show:
- ✅ **SUCCESS** - Application is running and ready
- 🚀 **APPLICATION IS READY TO ACCEPT CONNECTIONS**
- ❌ **ERROR** - If something went wrong

### Log Files on Instance

| Log File | Purpose |
|----------|---------|
| `/var/log/calo-guessr-setup.log` | Complete deployment setup log |
| `/var/log/calo-guessr-app.log` | Application runtime logs |
| `/opt/calo-guessr/deployment-info.txt` | Deployment summary and useful commands |

## Accessing Your Instance

## Accessing Your Streamlit Application

### SSH Access
After deployment, you can SSH to your instance:

```bash
# Get the SSH command from Pulumi output
pulumi stack output ssh_command

# Or manually using the private IP
ssh -i ~/.ssh/your-keypair ubuntu@<private-ip>
```

### Web Interface Access
Your Streamlit application will be accessible via web browser:

```bash
# Get the private IP
pulumi stack output private_ip

# Access the web interface
http://<private-ip>:8501
```

**Important**: Make sure port 8501 is open in your security groups for web access.

**Note**: You'll need to access the instance through your internal network since no floating IP is assigned.

## Application Management

### Service Management
The Python application runs as a systemd service:

```bash
# Check service status
sudo systemctl status calo-guessr

# View real-time logs
sudo journalctl -u calo-guessr -f

# View application logs
sudo tail -f /var/log/calo-guessr-app.log

# Restart service
sudo systemctl restart calo-guessr

# Stop service
sudo systemctl stop calo-guessr
```

### Quick Status Check
Use the built-in status checker:
```bash
/opt/calo-guessr/check_status.sh
```

### Deployment Information
View deployment details:
```bash
cat /opt/calo-guessr/deployment-info.txt
```

## File Locations on Instance

- **Application directory**: `/opt/calo-guessr/`
- **Python script**: `/opt/calo-guessr/calo_guessr_v*.py`
- **Virtual environment**: `/opt/calo-guessr/venv/`
- **Service file**: `/etc/systemd/system/calo-guessr.service`
- **Setup logs**: `/var/log/calo-guessr-setup.log`
- **Application logs**: `/var/log/calo-guessr-app.log`
- **Status checker**: `/opt/calo-guessr/check_status.sh`
- **Deployment info**: `/opt/calo-guessr/deployment-info.txt`

## Post-Deployment Workflow

1. **Deploy the application**:
   ```bash
   ./deploy.sh v1 my-keypair
   ```

2. **Monitor deployment progress**:
   ```bash
   ssh -i ~/.ssh/my-keypair ubuntu@<floating-ip> 'sudo tail -f /var/log/calo-guessr-setup.log'
   ```

3. **Wait for ready signal**: Look for "🚀 APPLICATION IS READY TO ACCEPT CONNECTIONS"

4. **Verify application status**:
   ```bash
   ssh -i ~/.ssh/my-keypair ubuntu@<floating-ip> '/opt/calo-guessr/check_status.sh'
   ```

5. **Monitor application logs**:
   ```bash
   ssh -i ~/.ssh/my-keypair ubuntu@<floating-ip> 'sudo journalctl -u calo-guessr -f'
   ```

## Cleanup

To destroy the deployed resources:

```bash
pulumi destroy
```

## Troubleshooting

### Common Issues and Solutions

1. **Deployment fails**: 
   - Check your OpenStack credentials with `source openrc.sh`
   - Verify network configuration and security groups

2. **SSH connection refused**: 
   - Ensure your security group allows SSH (port 22)
   - Verify your key pair exists in OpenStack

3. **Application not starting**: 
   - Check setup logs: `sudo tail -f /var/log/calo-guessr-setup.log`
   - Check service logs: `sudo journalctl -u calo-guessr -f`
   - Use status checker: `/opt/calo-guessr/check_status.sh`

4. **File not found errors**: 
   - Ensure `calo_guessr_v*.py` and `requirements.txt` exist in the project directory

5. **Key pair issues**:
   - Verify your SSH key pair exists in OpenStack
   - Check the key pair name matches what you specified

### Debugging Commands

```bash
# Check deployment status
sudo tail -f /var/log/calo-guessr-setup.log

# Check application logs
sudo tail -f /var/log/calo-guessr-app.log

# Check service status
sudo systemctl status calo-guessr

# View recent service logs
sudo journalctl -u calo-guessr --no-pager -n 50

# Quick status overview
/opt/calo-guessr/check_status.sh
```

## Configuration Options

You can customize the deployment by modifying the configuration in `__main__.py`:

- Change instance flavor
- Modify security groups
- Adjust network settings
- Update the systemd service configuration
- Customize logging behavior

## Environment Variables Template

The `openrc.sh` file provides a template for OpenStack authentication. Copy and customize it with your credentials:

```bash
cp openrc.sh my-openrc.sh
# Edit my-openrc.sh with your credentials
source my-openrc.sh
```

## Support

For issues related to:
- **Pulumi**: Check the [Pulumi documentation](https://www.pulumi.com/docs/)
- **OpenStack**: Consult your OpenStack provider's documentation
- **Application**: Review deployment and application logs as described above
- **Deployment Status**: Monitor the setup log for detailed status information