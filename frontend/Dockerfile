FROM node:18-alpine
WORKDIR /app
COPY package*.json tsconfig.json vite.config.ts ./
RUN npm ci
COPY src ./src
RUN npm run build
EXPOSE 5173
CMD ["npm", "run", "preview"]
