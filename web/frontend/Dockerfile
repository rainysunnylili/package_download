# Frontend Production Dockerfile - Multi-stage build
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY web/frontend/package.json /app/
COPY web/frontend/package-lock.json* /app/

# Install dependencies
RUN npm install

# Copy source code
COPY web/frontend /app/

# Build the application
RUN npm run build

# Production stage - Nginx
FROM nginx:alpine

# Copy built files from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY web/frontend/nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
