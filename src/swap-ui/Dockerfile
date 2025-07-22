# Build stage
FROM node:18-alpine as build

WORKDIR /app

# Install build dependencies for native modules
RUN apk add --no-cache python3 make g++ git linux-headers eudev-dev

# Copy package files
COPY app/package*.json ./
RUN npm ci

# Copy source code
COPY app/ ./

# Build the React app
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy mime.types file
COPY templates/mime.types /etc/nginx/mime.types

# Copy custom nginx configuration
COPY templates/nginx.conf /etc/nginx/nginx.conf

# Copy built React app
COPY --from=build /app/dist /usr/share/nginx/html

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
