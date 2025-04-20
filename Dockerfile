# FROM node:6-stretch
FROM node:18.13.0

WORKDIR /usr/src/goof

COPY package*.json ./

RUN npm ci

COPY . .

RUN mkdir /tmp/extracted_files

EXPOSE 3001
EXPOSE 9229

ENTRYPOINT ["npm", "start"]
