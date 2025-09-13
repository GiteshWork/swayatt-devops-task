# --- Stage 1: The Builder ---
# This stage installs dependencies and builds the application.
FROM node:18-alpine AS builder

# Set the working directory inside the container
WORKDIR /usr/src/app

# Copy package.json and package-lock.json to leverage Docker cache
COPY package*.json ./

# Install all project dependencies
RUN npm install

# Copy the rest of the application source code
COPY . .

# --- Stage 2: The Final Image ---
# This stage creates the small, optimized image that will be deployed.
FROM node:18-alpine

WORKDIR /usr/src/app

# Copy only the necessary node_modules from the 'builder' stage
COPY --from=builder /usr/src/app/node_modules ./node_modules

# Copy the application code from the 'builder' stage
COPY --from=builder /usr/src/app .

# Expose the port that the application runs on
EXPOSE 3000

# The command to run the application when the container starts
CMD [ "node", "app.js" ]