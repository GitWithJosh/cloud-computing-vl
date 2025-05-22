import pulumi
import pulumi_openstack as openstack
import os

# Configuration
config = pulumi.Config()
version = config.get("version") or "v1"  # Default to v1 if not specified
script_name = f"calo_guessr_{version}.py"

# OpenStack configuration
image_id = "c57c2aef-f74a-4418-94ca-d3fb169162bf"
flavor_name = "cb1.medium"
key_pair = config.require("key_pair")  # User must specify their SSH key pair
network_name = "provider_912"
security_groups = ["default"]

# Get the network
network = openstack.networking.get_network(name=network_name)

# Read local files to upload
def read_file(filename):
    try:
        with open(filename, 'r') as f:
            return f.read()
    except FileNotFoundError:
        pulumi.log.warn(f"File {filename} not found")
        return ""

# Read files and encode them for cloud-init
script_content = read_file(script_name)
requirements_content = read_file("requirements.txt")

# Validate files exist
if not script_content:
    raise Exception(f"Required file {script_name} not found or empty")
if not requirements_content:
    pulumi.log.warn("requirements.txt not found - continuing without dependencies")

# Create cloud-init user data script with embedded files
user_data = f"""#!/bin/bash
set -e

# Setup logging
LOG_FILE="/var/log/calo-guessr-setup.log"
exec 1> >(tee -a $LOG_FILE)
exec 2>&1

echo "=== Calorie Guesser Setup Started at $(date) ==="
echo "Deploying version: {version}"

# Update system
echo "$(date): Updating system packages..."
apt-get update
apt-get upgrade -y
echo "$(date): System packages updated successfully"

# Install Python and pip
echo "$(date): Installing Python and dependencies..."
apt-get install -y python3 python3-pip python3-venv git curl
echo "$(date): Python installation completed"

# Create application directory
echo "$(date): Setting up application directory..."
mkdir -p /opt/calo-guessr
cd /opt/calo-guessr

# Write the Python script
echo "$(date): Creating Python script {script_name}..."
cat > {script_name} << 'PYTHON_SCRIPT_EOF'
{script_content}
PYTHON_SCRIPT_EOF

# Write requirements.txt if content exists
{f'''echo "$(date): Creating requirements.txt..."
cat > requirements.txt << 'REQUIREMENTS_EOF'
{requirements_content}
REQUIREMENTS_EOF''' if requirements_content else 'echo "$(date): No requirements.txt provided, skipping..."'}

# Create virtual environment
echo "$(date): Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate
echo "$(date): Virtual environment created successfully"

# Install requirements
echo "$(date): Installing Python requirements..."
if [ -f requirements.txt ] && [ -s requirements.txt ]; then
    pip install -r requirements.txt
    echo "$(date): Requirements installed successfully"
else
    echo "$(date): No requirements to install, skipping..."
fi

# Make the Python script executable
echo "$(date): Setting up Python script..."
if [ -f {script_name} ] && [ -s {script_name} ]; then
    chmod +x {script_name}
    echo "$(date): Python script {script_name} is ready"
else
    echo "$(date): ERROR - {script_name} not found or empty"
    exit 1
fi

# Create systemd service for the application
echo "$(date): Creating systemd service..."
cat > /etc/systemd/system/calo-guessr.service << EOF
[Unit]
Description=Calorie Guesser Application {version}
After=network.target

[Service]
Type=simple
User=ubuntu
Group=ubuntu
WorkingDirectory=/opt/calo-guessr
Environment=PATH=/opt/calo-guessr/venv/bin
ExecStart=/opt/calo-guessr/venv/bin/streamlit run {script_name} --server.port=8501 --server.address=0.0.0.0 --server.headless=true
Restart=always
RestartSec=10
StandardOutput=append:/var/log/calo-guessr-app.log
StandardError=append:/var/log/calo-guessr-app.log

[Install]
WantedBy=multi-user.target
EOF

# Set ownership
echo "$(date): Setting file permissions..."
chown -R ubuntu:ubuntu /opt/calo-guessr
chmod 644 /etc/systemd/system/calo-guessr.service

# Enable and start the service
echo "$(date): Starting Calorie Guesser service..."
systemctl daemon-reload
systemctl enable calo-guessr.service
systemctl start calo-guessr.service

# Wait a moment and check service status
sleep 5
if systemctl is-active --quiet calo-guessr.service; then
    echo "$(date): ✅ SUCCESS - Calorie Guesser application is running and ready!"
    echo "$(date): Service status: $(systemctl is-active calo-guessr.service)"
    echo "$(date): 🚀 APPLICATION IS READY TO ACCEPT CONNECTIONS"
else
    echo "$(date): ❌ ERROR - Service failed to start"
    echo "$(date): Service status: $(systemctl is-active calo-guessr.service)"
    echo "$(date): Checking service logs..."
    journalctl -u calo-guessr.service --no-pager -n 20
fi

# Create a simple HTML page to indicate the correct port
echo "$(date): Creating HTML page for port instructions..."
cat > /opt/calo-guessr/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Calorie Guesser</title>
</head>
<body style="font-family: Arial, sans-serif; text-align: center; margin-top: 50px;">
    <h1>Welcome to Calorie Guesser</h1>
    <p>The application is running on port <strong>8501</strong>.</p>
</body>
</html>
HTML_EOF

# Install and configure nginx to serve the HTML page
echo "$(date): Installing nginx..."
apt-get install -y nginx
echo "$(date): Configuring nginx..."
cat > /etc/nginx/sites-available/default << 'NGINX_CONF'
server {{
    listen 80 default_server;
    listen [::]:80 default_server;

    root /opt/calo-guessr;
    index index.html;

    server_name _;

    location / {{
        try_files $uri $uri/ =404;
    }}
}}
NGINX_CONF

# Restart nginx to apply the configuration
echo "$(date): Restarting nginx..."
systemctl restart nginx
echo "$(date): nginx setup completed successfully"

# Create status check script
cat > /opt/calo-guessr/check_status.sh << 'EOF'
#!/bin/bash
echo "=== Calorie Guesstr Status Check ==="
echo "Service Status: $(systemctl is-active calo-guessr.service)"
echo "Service Enabled: $(systemctl is-enabled calo-guessr.service)"
echo ""
echo "Recent logs:"
journalctl -u calo-guessr.service --no-pager -n 10
EOF

chmod +x /opt/calo-guessr/check_status.sh
chown ubuntu:ubuntu /opt/calo-guessr/check_status.sh

# Create deployment info file
cat > /opt/calo-guessr/deployment-info.txt << EOF
Deployment Information
=====================
Version: {version}
Script: {script_name}
Deployed at: $(date)
Instance ID: $(curl -s http://169.254.169.254/openstack/latest/meta_data.json | python3 -c "import sys, json; print(json.load(sys.stdin).get('uuid', 'unknown'))" 2>/dev/null || echo "unknown")

Application Access:
- Streamlit Web Interface: http://INSTANCE_IP:8501
- Default port: 8501
- Accessible from any IP (0.0.0.0)

Useful Commands:
- Check status: sudo systemctl status calo-guessr
- View logs: sudo journalctl -u calo-guessr -f
- Application logs: sudo tail -f /var/log/calo-guessr-app.log
- Quick status: /opt/calo-guessr/check_status.sh
- Test locally: curl http://localhost:8501

Log Files:
- Setup log: /var/log/calo-guessr-setup.log
- Application log: /var/log/calo-guessr-app.log

Streamlit Configuration:
- Port: 8501
- Address: 0.0.0.0 (accessible from network)
- Headless mode: enabled
EOF

chown ubuntu:ubuntu /opt/calo-guessr/deployment-info.txt

echo "=== Setup completed successfully at $(date) ==="
echo "=== Calorie Guesser {version} is ready for use! ==="
"""

# Create the compute instance
instance = openstack.compute.Instance(
    "calo-guessr-instance",
    name=f"calo-guessr-{version}",
    image_id=image_id,
    flavor_name=flavor_name,
    key_pair=key_pair,
    security_groups=security_groups,
    networks=[{"name": network_name}],
    user_data=user_data,
    metadata={
        "version": version,
        "application": "calo-guessr"
    },
    opts=pulumi.ResourceOptions(
        depends_on=[]
    )
)

# Export important values
pulumi.export("instance_id", instance.id)
pulumi.export("instance_name", instance.name)
pulumi.export("private_ip", instance.access_ip_v4)
pulumi.export("ssh_command", pulumi.Output.concat("ssh -i ~/.ssh/", key_pair, " ubuntu@", instance.access_ip_v4))
pulumi.export("version_deployed", version)