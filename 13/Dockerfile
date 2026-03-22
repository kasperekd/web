FROM nginx:alpine

COPY . /usr/share/nginx/html
# Открываем порт 80 внутри контейнера
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]