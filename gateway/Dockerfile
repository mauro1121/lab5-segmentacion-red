FROM nginx:alpine

# curl y nc instalados solo para las pruebas del laboratorio
RUN apk add --no-cache curl netcat-openbsd

COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
