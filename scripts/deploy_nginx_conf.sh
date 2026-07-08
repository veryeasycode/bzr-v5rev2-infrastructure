#!/bin/bash

# Clean up files
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/sites-enabled/bzr_v5.conf
rm -f /etc/nginx/sites-available/bzr_v5.conf
rm -f /etc/nginx/conf.d/bzr_v5.conf
rm -f /etc/ssl/certificate.crt
rm -f /etc/ssl/private/private.key

# Load environment variables
if [ -f .env ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line=$(echo "$line" | sed -e "s/^[[:space:]]*//" -e "s/[[:space:]]*$//")
    if [[ -z "$line" || "$line" =~ ^# ]]; then
      continue
    fi
    line=$(echo "$line" | sed -e "s/[[:space:]]*#.*$//" -e "s/[[:space:]]*$//")
    export "$line"
  done < .env
fi

# The cloud server serves the EMC API from its local upstream; every other
# server forwards it to the cloud (proxying to itself would loop forever)
if [ "$SERVER_NAME" = "$CLOUD_SERVER_NAME" ]; then
  EMC_API_SNIPPET="emc_local.conf"
else
  EMC_API_SNIPPET="emc_cloud.conf"
fi

# Deploy configs
cp -rf templates/nginx/* /etc/nginx
sed -i "s|{{JWT_TOKEN}}|$JWT_SECRET|g" /etc/nginx/njs/bzr_v5_jwt_decoder.js
sed -i "s|{{CLOUD_SERVER_NAME}}|$CLOUD_SERVER_NAME|g" /etc/nginx/snippets/emc_cloud.conf
sed -i \
-e "s|{{SERVICE_AUTHENTICATOR_PORT}}|$SERVICE_AUTHENTICATOR_PORT|g" \
-e "s|{{SERVICE_FUNCTIONS_PORT}}|$SERVICE_FUNCTIONS_PORT|g" \
-e "s|{{SERVICE_MONGOSTREAM_PORT}}|$SERVICE_MONGOSTREAM_PORT|g" \
-e "s|{{SERVICE_BACKOFFICE_PORT}}|$SERVICE_BACKOFFICE_PORT|g" \
-e "s|{{SERVICE_BACKOFFICE2_API_PORT}}|$SERVICE_BACKOFFICE2_API_PORT|g" \
-e "s|{{SERVICE_BACKOFFICE2_WEB_PORT}}|$SERVICE_BACKOFFICE2_WEB_PORT|g" \
-e "s|{{SERVICE_EDC_API_PORT}}|$SERVICE_EDC_API_PORT|g" \
-e "s|{{SERVICE_EDC_WEB_PORT}}|$SERVICE_EDC_WEB_PORT|g" \
-e "s|{{SERVICE_LINE_MENU_BOT_PORT}}|$SERVICE_LINE_MENU_BOT_PORT|g" \
-e "s|{{SERVICE_MESSAGE_GATEWAY_PORT}}|$SERVICE_MESSAGE_GATEWAY_PORT|g" \
-e "s|{{SERVICE_LINE_MENU_API_PORT}}|$SERVICE_LINE_MENU_API_PORT|g" \
-e "s|{{SERVICE_LINE_MENU_WEB_PORT}}|$SERVICE_LINE_MENU_WEB_PORT|g" \
-e "s|{{SERVICE_LINE_MENU_WEB_LITE_PORT}}|$SERVICE_LINE_MENU_WEB_LITE_PORT|g" \
-e "s|{{SERVICE_LINE_DELIVERY_WEB_PORT}}|$SERVICE_LINE_DELIVERY_WEB_PORT|g" \
-e "s|{{SERVICE_RESERVATION_API_PORT}}|$SERVICE_RESERVATION_API_PORT|g" \
-e "s|{{SERVICE_RESERVATION_WEB_BACKOFFICE_PORT}}|$SERVICE_RESERVATION_WEB_BACKOFFICE_PORT|g" \
-e "s|{{SERVICE_RESERVATION_WEB_FORM_PORT}}|$SERVICE_RESERVATION_WEB_FORM_PORT|g" \
-e "s|{{EMC_API_SNIPPET}}|$EMC_API_SNIPPET|g" \
/etc/nginx/sites-available/bzr_v5.conf
ln -s /etc/nginx/sites-available/bzr_v5.conf /etc/nginx/conf.d/bzr_v5.conf

# Deploy SSL
cp certs/certificate.crt /etc/ssl/certificate.crt
cp certs/private.key /etc/ssl/private/private.key

# Reload service to apply new configuration
systemctl reload nginx