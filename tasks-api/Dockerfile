FROM node:14-alpine

WORKDIR /app

# Copy package.json first for better caching
COPY package.json .

# Install dependencies
RUN npm install

# Copy application code
COPY . .

# Create tasks directory and initialize empty file
RUN mkdir -p /app/tasks && touch /app/tasks/tasks.txt

EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget --quiet --tries=1 --spider http://localhost:8000/health || exit 1

CMD [ "node", "tasks-app.js" ]

# FROM node:14-alpine

# WORKDIR /app

# COPY tasks /app/tasks

# COPY package.json .

# RUN npm install

# COPY . .

# EXPOSE 8000

# CMD [ "node", "tasks-app.js" ]