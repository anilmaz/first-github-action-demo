FROM nginx:1.27-alpine

RUN rm -rf /usr/share/nginx/html/*

COPY index.html /usr/share/nginx/html/index.html
COPY README.md /usr/share/nginx/html/README.md
COPY 10-telemetry.sh /docker-entrypoint.d/10-telemetry.sh

RUN sed -i 's/\r$//' /docker-entrypoint.d/10-telemetry.sh && chmod +x /docker-entrypoint.d/10-telemetry.sh

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]