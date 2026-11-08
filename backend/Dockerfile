FROM node:20-alpine

# Herramientas para las pruebas de red (nc = netcat, curl)
RUN apk add --no-cache netcat-openbsd curl

WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./

EXPOSE 3000
CMD ["node", "server.js"]
