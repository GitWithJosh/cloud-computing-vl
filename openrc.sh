export OS_AUTH_URL=https://stack.dhbw.cloud:5000
export OS_PROJECT_ID=d11c8af5f24f4756a6d51b880162f71f
export OS_PROJECT_NAME=ma_wdski23a_cloud
export OS_USER_DOMAIN_NAME="Default"

export OS_USERNAME="pfisterer-cloud-lecture"
export OS_PASSWORD="ss2025"
export OS_AUTH_TYPE=password
export OS_IDENTITY_API_VERSION=3

echo "OpenStack environment variables have been set"
echo "Auth URL: $OS_AUTH_URL"
echo "Username: $OS_USERNAME"
echo "Project: $OS_PROJECT_NAME"

# Verify connection
if command -v openstack &> /dev/null; then
    echo "Testing OpenStack connection..."
    openstack token issue --format value --column expires 2>/dev/null && echo "✅ OpenStack connection successful" || echo "❌ OpenStack connection failed"
fi