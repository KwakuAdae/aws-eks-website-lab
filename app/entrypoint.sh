#!/bin/sh
# Show which pod served the page (POD_NAME comes from the Kubernetes Downward API).
sed "s/__POD_NAME__/${POD_NAME:-local}/" /usr/share/nginx/html/index.html.tpl > /usr/share/nginx/html/index.html
exec nginx -g 'daemon off;'
