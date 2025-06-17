#!/bin/bash
source openrc.sh
terraform init
terraform destroy -auto-approve