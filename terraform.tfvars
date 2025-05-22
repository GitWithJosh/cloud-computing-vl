# OpenStack instance configuration
image_id      = "c57c2aef-f74a-4418-94ca-d3fb169162bf"  # Replace with your OpenStack image ID
flavor_name   = "cb1.medium"       # Replace with appropriate flavor
key_pair      = "shooosh"  # Replace with your SSH key pair name
network_name  = "provider_912"   # Replace with your network name
security_groups = ["default"]    # Adjust as needed

# Application configuration
app_version   = "v1.0.0"