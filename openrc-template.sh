export OS_AUTH_URL=https://<dein-openstack-endpunkt>:5000/v3
export OS_PROJECT_ID=dein-projekt-id
export OS_PROJECT_NAME=dein-projekt-name
export OS_USER_DOMAIN_NAME="Default"

export OS_USERNAME="name"
export OS_PASSWORD="pass"
export OS_AUTH_TYPE=password
export OS_IDENTITY_API_VERSION=3

echo "OpenStack environment variables have been set"
echo "Auth URL: $OS_AUTH_URL"
echo "Username: $OS_USERNAME"
echo "Project: $OS_PROJECT_NAME"

# Verify connection (optional)
if command -v openstack &> /dev/null; then
    echo "Testing OpenStack connection..."
    openstack token issue --format value --column expires 2>/dev/null && echo "✅ OpenStack connection successful" || echo "❌ OpenStack connection failed"
fi