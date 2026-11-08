Yes, typically you run a separate Nginx container as a reverse proxy, while keeping each application in its own Docker Compose project.

However, Nginx does not need its own application Dockerfile. You can use the official Nginx image directly.

## Recommended architecture

[Secure web project hosting with docker-compose, nginx, and LetsEncrypt - Halfnelson’s Blog](https://images.openai.com/static-rsc-4/8bhuCZMFyZ7zjo8hjmOsTYOhcWlqkqWPTjPiRhokfklCnYQNEJTETMT0BOHZRGHaH9dXWchCPSZzrfKAkBOPaxtQv0EpZxsPoxeAgF4eQ-LYq8jaEV4cg9qKxxCyyVcdZ7A5QbeElde9-UFT75w3vG6qH71eDfohZ4eQ3DmsELw?purpose=inline)

```
                    Internet
                       |
                 DNS: abc.com
                       |
                 Public IP
                       |
                Nginx Container
                (Port 80/443)
                       |
           +-----------+-----------+
           |                       |
    a.abc.com                 b.abc.com
           |                       |
     App A Container         App B Container
     Port 3000               Port 3000
```

## 1. Nginx Docker Compose

You can create a separate directory:

```
/opt/
├── nginx/
│   ├── docker-compose.yml
│   └── conf.d/
│       └── default.conf
├── app-a/
│   └── docker-compose.yml
└── app-b/
    └── docker-compose.yml
```

Nginx Compose:

```
services:
  nginx:
    image: nginx:alpine
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./conf.d:/etc/nginx/conf.d:ro
    networks:
      - proxy

networks:
  proxy:
    external: true
```

Create the shared network:

```
docker network create proxy
```

## 2. Nginx configuration

`/opt/nginx/conf.d/default.conf`

```
server {
    listen 80;
    server_name a.abc.com;

    location / {
        proxy_pass http://app-a:3000;
    }
}

server {
    listen 80;
    server_name b.abc.com;

    location / {
        proxy_pass http://app-b:3000;
    }
}
```

## 3. App A Compose

```
services:
  app-a:
    build: .
    container_name: app-a
    expose:
      - "3000"
    networks:
      - proxy

networks:
  proxy:
    external: true
```

## 4. App B Compose

```
services:
  app-b:
    build: .
    container_name: app-b
    expose:
      - "3000"
    networks:
      - proxy

networks:
  proxy:
    external: true
```

## Important details

- `expose: 3000` does not publish the port to the internet. It makes the intended internal port explicit.
- Both applications can listen on port 3000 because they run in separate containers.
- Nginx can access both containers through the shared Docker network.
- Only Nginx needs public ports `80` and `443`.
- You can deploy, restart, or update each application independently.

One important recommendation: use a shared external Docker network so Nginx can communicate with application containers across different Compose projects.

If you're building this for production, I would recommend this architecture:

- One Nginx reverse proxy container
- One Compose project per application
- One shared Docker network
- Certbot or another ACME client for automatic HTTPS certificates

This is a clean, scalable setup for hosting multiple domains on one VPS or EC2 instance.