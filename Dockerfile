FROM nginx:1.27-alpine

# Remove default static assets
RUN rm -rf /usr/share/nginx/html/*

# Copy application entry point and documentation
COPY index.html /usr/share/nginx/html/index.html
COPY README.md /usr/share/nginx/html/README.md

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
