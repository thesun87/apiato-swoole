FROM nginx:1.25-alpine

RUN rm /etc/nginx/conf.d/default.conf

COPY docker-fpm/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker-fpm/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf

EXPOSE 80
