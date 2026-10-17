# Unprivileged nginx: runs as non-root (UID 101) and listens on 8080 (Kubernetes best practice)
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=101:101 index.html /usr/share/nginx/html/index.html.tpl
COPY --chown=101:101 styles.css /usr/share/nginx/html/
COPY --chmod=755 entrypoint.sh /entrypoint.sh

# Let the non-root user render index.html at startup
USER root
RUN chown 101:101 /usr/share/nginx/html && rm -f /usr/share/nginx/html/index.html
USER 101

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
