[Шпаргалка по разметке mark down](https://gist.github.com/OlgaMurzina/a094b7bfa6f15b25c683309885d68dbb#links)
# 📝 Лабораторная работа №1



В этот раз, мы всей командой решили подготовить минисервер в виде виртуальной машины, чтобы не ставить вторую систему на ноутбук. С первого семестра у нас остался VirtualBox. Мы создали новую виртуальную машину и установили на нее ОС Ubuntu 26.04.   

## Что мы сделали
*	Настроили работу сервиса "Наши заметки" по HTTPS с самоподписанным сертификатом, а HTTP (порт 80) принудительно перенаправили на HTTPS (443). 
*	Фронт и бэк развели на одном хосте: статику фронтенда nginx отдаёт сам, а запросы на /api проксирует на бэкенд. 
*	Настроили балансировку (upstream) двух копий нашего бэкенда на портах 5101 и 5102. Теперь nginx балансирует /api между ними. 
*	Настроили alias для псевдонима /docs из отдельной папки /var/www/docs. 
*	Настроили виртуальные хосты notes.app и site2.local на одном сервере. Также, реализовали заглушку default_server, чтобы nginx при запросе чужого домена вернул пустой ответ и не отдал лишнего. 
*	Настроили ограничение частоты запросов (limit_req) на notes.app/api. 
*	Реализовали и настроили вывод своей страницы 404 вместо стандартной на хостах notes.app и site2.local. 
*	Закрыли путь /admin базовой авторизацией (auth_basic + htpasswd).

## Результаты
1. Файлы настройки nginx находятся в папке ./etc/nginx.
2. Скриншоты процесса настройки находятся в папке ./Screenshots.
3. Скрипт проверок находится в файле ./check.sh.
4. Результаты проверок находятся в файле ./check.log.

## Пояснения к проверкам
На наш взгляд, в пояснении нуждается только момент проксирования /api на две копии нашего бэкенда, остальное понятно из содержимого файла ./check.log   
Чтобы было видно, что nginx направляет запросы на оба инстанса бэкенда (если они конечно стартованы), мы реализовали в бэкенде эндпоинт /health, который возвращает в качестве ответа JSON вида:
  ```json
        {
                    "status": "ok",
                    "request_port": "REQUEST_PORT"
        }
  ```
где REQUEST_PORT - порт, на котором реально принял запрос экземпляр нашего бэкенда.
Мы настроили, чтобы обращение к этому эндпоинту nginx принимал на /api/backend_health и уже затем проксировал их на /notes_backend/health. Мы запустили две копии нашего бэкенда на портах 5101 и 5102, но обращаемся по https://notes.app/api/backend_health 
Из файла check.log мы видим, что при поднятых 2-х копиях нашего бэкенда, nginx чередует запросы между ними и ответы мы получаем последовательно с портов 5101 и 5102. Это показывает, что реально запросы уходят на оба инстанса нашего бэкенда. 
Как только мы погасили один инстанс на порту 5101, то в ответах на https://notes.app/api/backend_health мы стали видеть только ответы от инстанса, который остался на порту 5102.
Также, мы проводили тестирование нашего сервиса, который нормально функционировал даже при одном инстансе бэкенда. 

😢 Подробное описание наших страданий находится в части "Как это было". Добро пожаловать под кат...

# 🛠️ Как это было
## День 1-й. Ставим nginx и пробуем выпустить ssl-сертификат  
### Ставим nginx  
Первым делом установили nginx.
   ```bash
    sudo apt install nginx
   ```
После установки проверяем статус службы nginx:
   ```bash
    sudo service nginx status
   ```
Все хорошо, служба работает (вот за это мы и любим Ubuntu в частности, и Linux в целом):
   ```text
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: active (running) since Mon 2026-09-28 10:30:50 UTC; 17s ago
 Invocation: 2918cc0afb4940d9ac9a5727991a90a5
       Docs: man:nginx(8)
    Process: 7691 ExecStartPre=/usr/sbin/nginx -t -q -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
    Process: 7693 ExecStart=/usr/sbin/nginx -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
   Main PID: 7728 (nginx)
      Tasks: 9 (limit: 6353)
     Memory: 7.3M (peak: 16.5M)
        CPU: 54ms
     CGroup: /system.slice/nginx.service
             ├─7728 "nginx: master process /usr/sbin/nginx -g daemon on; master_process on;"
             ├─7731 "nginx: worker process"
             ├─7732 "nginx: worker process"
             ├─7733 "nginx: worker process"
             ├─7734 "nginx: worker process"
             ├─7735 "nginx: worker process"
             ├─7736 "nginx: worker process"
             ├─7737 "nginx: worker process"
             └─7738 "nginx: worker process"

Sep 28 10:30:50 Ubuntu systemd[1]: Starting nginx.service - A high performance web server and a reverse proxy server...
Sep 28 10:30:50 Ubuntu systemd[1]: Started nginx.service - A high performance web server and a reverse proxy server.
   ```
   Посмотрим что находится в файле настроек nginx:
   ```bash
    cat /etc/nginx/nginx.conf
   ```
<details>
  <summary>Видим содержимое файла /etc/nginx/nginx.conf</summary>

   ```text
        user www-data;
        worker_processes auto;
        worker_cpu_affinity auto;
        pid /run/nginx.pid;
        error_log /var/log/nginx/error.log;
        include /etc/nginx/modules-enabled/*.conf;
        
        events {
            worker_connections 768;
            # multi_accept on;
        }
        
        http {
        
            ##
            # Basic Settings
            ##
        
            sendfile on;
            tcp_nopush on;
            types_hash_max_size 2048;
            server_tokens build; # Recommended practice is to turn this off
        
            # server_names_hash_bucket_size 64;
            # server_name_in_redirect off;
        
            include /etc/nginx/mime.types;
            default_type application/octet-stream;
        
            ##
            # SSL Settings
            ##
        
            ssl_protocols TLSv1.2 TLSv1.3; # Dropping SSLv3 (POODLE), TLS 1.0, 1.1
            ssl_prefer_server_ciphers off; # Don't force server cipher order.
        
            ##
            # Logging Settings
            ##
        
            access_log /var/log/nginx/access.log;
        
            ##
            # Gzip Settings
            ##
        
            gzip on;
        
            # gzip_vary on;
            # gzip_proxied any;
            # gzip_comp_level 6;
            # gzip_buffers 16 8k;
            # gzip_http_version 1.1;
            # gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
        
            ##
            # Virtual Host Configs
            ##
        
            include /etc/nginx/conf.d/*.conf;
            include /etc/nginx/sites-enabled/*;
        }
        
        
        #mail {
        #	# See sample authentication script at:
        #	# http://wiki.nginx.org/ImapAuthenticateWithApachePhpScript
        #
        #	# auth_http localhost/auth.php;
        #	# pop3_capabilities "TOP" "USER";
        #	# imap_capabilities "IMAP4rev1" "UIDPLUS";
        #
        #	server {
        #		listen     localhost:110;
        #		protocol   pop3;
        #		proxy      on;
        #	}
        #
        #	server {
        #		listen     localhost:143;
        #		protocol   imap;
        #		proxy      on;
        #	}
        #}
   ```
</details>
<details>
  <summary>Пробуем посмотреть что выдаст браузер по этому url: http://localhost/</summary>

![img.png](Screenshots/welcome_nginx.png)

</details>

### Выпускаем самоподписной ssl-сертификат
Пробуем выпустить самоподписной ssl-сертификат для локальных имен: Notes.app, locallhost и локального ip 127.0.0.1:
   ```bash
    openssl req -x509 -newkey rsa:4096 \
      -keyout notes-app.key \
      -out notes-app.crt \
      -days 1095 -nodes \
      -subj "/CN=Notes.app" \
      -addext "subjectAltName=DNS:Notes.app,DNS:localhost,IP:127.0.0.1"   
  ```
В итоге получили 2 файла:
1. notes-app.key
2. notes-app.crt

<details>
  <summary>Это скриншот создания самоподписного ssl-сертификата"</summary>

![img.png](Screenshots/ssl_certcreate.png)

</details>

## День 2-й. Оживляем наш frontend по https
### Сборка frontend
Для начала надо собрать наш frontend по-взрослому командой:
   ```bash
  npm run build
  ```
Установили npm:
   ```bash
  sudo apt install npm
  ```
В папке frontend выполнили установку зависимостей:
   ```bash
  npm install
  ```
Затем в папке frontend выполнили сборку:
   ```bash
  npm run build
  ```

<details>
  <summary>ops неудачка </summary>

![img.png](Screenshots/build_fail.png)

</details>

Для экономии времени просто отключили проверку типов в файле frontend/package.json, исправив строку сборки так:
"build": "~~tsc -b &&~~ vite build", чтобы в итоге получилось:
   ```text
    ...
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "lint": "oxlint",
    "preview": "vite preview"
  }
  ...
```
Теперь сборка проходит и результат сборки находится в папке dist. Перенесли папку dist со всем содержимым в папку /var/www/Notes.app:

   ```bash
    sudo mv dist /var/www/Notes.app 
  ```
### Подключаем самоподписной ssl-сертификат к nginx
Положили файл notes-app.key в каталог /etc/ssl/private/:
   ```bash
    sudo mv notes-app.key /etc/ssl/private/notes-app.key 
  ```
Положили файл notes-app.crt в каталог /etc/ssl/certs/:
   ```bash
    sudo mv notes-app.crt /etc/ssl/certs/notes-app.crt 
  ```
Создали файл настройки нашего сервиса:
   ```bash
    sudo nano /etc/nginx/sites-available/notes-app 
  ```
![img.png](Screenshots/notes_app1.png)

Сделали симлинк в sites-enabled:
   ```bash
    sudo ln -s /etc/nginx/sites-available/notes-app  /etc/nginx/sites-enabled/notes-app 
  ```

Дали команду nginx перечитать конфигурацию и перезапуститься:
   ```bash
    sudo nginx -t
    sudo service nginx reload
   ```
Теперь в браузере по адресу https://localhost видим страницу своего frontend, согласившись открыть небезопасный сайт, т.к. браузер не доверяет самоподписному сертификату. 
## День 3-й. Настраиваем nginx на проксирование Backend
### Разбираемся с базой данных PostgreSQL на Ubuntu
Поставили PostgreSQL:
   ```bash
    sudo apt install -y postgresql postgresql-contrib    
   ```
Дальше настроим доступ на наш PostgreSQL сервер снаружи, чтобы можно было подключиться используя PgAdmin:
   ```bash
    sudo cp /etc/postgresql/18/main/postgresql.conf /etc/postgresql/18/main/postgresql.conf.bak
    sudo nano /etc/postgresql/18/main/postgresql.conf   
   ```
Нашли строку в /etc/postgresql/18/main/postgresql.conf:

   ```text
    #listen_addresses = 'localhost'
   ```
и заменили ее так:
   ```text
    listen_addresses = '*'
   ```
Разрешили подключения в pg_hba.conf
   ```bash
    sudo cp /etc/postgresql/18/main/pg_hba.conf /etc/postgresql/18/main/pg_hba.conf.bak
    sudo nano /etc/postgresql/18/main/pg_hba.conf   
   ```
Нашли строку в /etc/postgresql/18/main/pg_hba.conf:

   ```text
    host    all             all             127.0.0.1/32            scram-sha-256
   ```
и заменили ее так:
   ```text
    host    all             all             0.0.0.0/0            scram-sha-256
   ```
Заменили пароль пользователю postgres:
   ```bash
    sudo -u postgres psql
   ```
   ```sql
    ALTER USER postgres WITH PASSWORD 'passwordexample';
   ```
где 'passwordexample' дан только для примера. Реальный пароль другой и здесь опубликован не будет.

Перечитали конфигурацию:
   ```bash
    sudo systemctl reload postgresql
   ```
Теперь можем подключиться с любого компа, который видит ip-адрес нашей виртуалки к установленному на ней PostgreSQL серверу.
Подключились PgAdmin 4 и создали базу для бэкенда, как в лабе 0.
Выполнили шаги по установке бэкенда, как в лабе 0.

### Добавляем проксирование backend в конфигурацию нашего сервиса
Пытаемся доделать настройки нашего сервиса:
   ```bash
    sudo nano /etc/nginx/sites-available/notes-app 
  ```
Сейчас файл настройки нашего сайта выглядит так:

![img.png](Screenshots/notes_app2.png)

Дали команду nginx перечитать конфигурацию и перезапуститься:
   ```bash
    sudo nginx -t
    sudo service nginx reload
   ```
Теперь сервис "Наши заметки" полностью работает (если не забыть запустить хотя бы одни экземпляр нашего backend) и доступен по https, например https://127.0.0.1 или https://localhost.
Осталось настроить редирект с http на https. 

### Hастраиваем редирект с http на https
Снова открываем на редактирование файл настройки нашего сервиса, чтобы сделать редирект с http на https:
   ```bash
    sudo nano /etc/nginx/sites-available/notes-app 
  ```
Чтобы не мешал дефолтный сайт nginx отключаем его:
   ```bash
    sudo unlink /etc/nginx/sites-enabled/default 
  ```
Дали команду nginx перечитать конфигурацию и перезапуститься:
   ```bash
    sudo nginx -t
    sudo service nginx reload
   ```
Теперь сервис "Наши заметки" полностью работает (если не забыть запустить хотя бы одни экземпляр нашего backend) и доступен как по http, так и по https.

   ```bash
   cd ./Lab_0/backend
   source .venv/bin/activate
   flask --app run.py run --port 5101
   flask --app run.py run --port 5102
   ```

На сегодня пока все.

На текущий момент, файл настройки нашего сайта выглядит так:
![img.png](Screenshots/notes_app2.png)

## День 4-й. Почти всё, но ещё не всЁ
### Добавляем свою страницу на обработку ошибки 404 вместо стандартной
<details>
  <summary>Сейчас отображение ошибки 404 выглядит вот так</summary>

![img.png](Screenshots/404_nginx.png)

</details>

Скопировали файл Lab_1/404.html в корень нашего сайта:

```bash
    sudo cp 404.html /var/www/Notes.app
   ```

<details>
  <summary>После нашего волшебства над файлом /etc/nginx/sites-available/notes-app отображение ошибки 404 стало выглядеть красиво</summary>

![img.png](Screenshots/404_best.png)

</details>

В итоге, файл настройки сервиса "Наши заметки" выглядит так:

![img.png](Screenshots/notes_app.png)

### Настраиваем второй виртуальный сервер (второй сайт)
Эх, что-то с памятью моей стало, хорошо, что записала. Вспоминаем, что делали в первый день:
Выпустили сертификат для нашего второго сайта. Назовем домен: site2.local и добавим ещё для интереса www.site2.local:
   ```bash
    openssl req -x509 -newkey rsa:4096 \
      -keyout site2-local.key \
      -out site2-local.crt \
      -days 1095 -nodes \
      -subj "/CN=site2.local" \
      -addext "subjectAltName=DNS:site2.local,DNS:www.site2.local"   
  ```
Положили файл site2-local.key в каталог /etc/ssl/private/:
   ```bash
    sudo mv site2-local.key /etc/ssl/private/site2-local.key 
  ```
Положили файл site2-local.crt в каталог /etc/ssl/certs/:
   ```bash
    sudo mv site2-local.crt /etc/ssl/certs/site2-local.crt 
  ```
Создали папку нашего второго сайта и положили туда Lab_1/site2/index.html и Lab_1/404.html
```bash
  sudo mkdir /var/www/site2.local
  sudo cp  Lab_1/site2/index.html Lab_1/404.html /var/www/site2.local
  ```
Создали файл настройки сайта site2.local, скопировав наш /etc/nginx/sites-available/notes-app:
   ```bash
    sudo cp /etc/nginx/sites-available/notes-app /etc/nginx/sites-available/site2-local
  ```
и поправили его так:

![img.png](Screenshots/site2-local.png)

Сделали симлинк в sites-enabled:
   ```bash
    sudo ln -s /etc/nginx/sites-available/site2-local  /etc/nginx/sites-enabled/site2-local 
  ```

Дали команду nginx перечитать конфигурацию и перезапуститься:
   ```bash
    sudo nginx -t
    sudo service nginx reload
   ```
Вставили резолвинг на site2.local и www.site2.local в /etc/hosts

![img.png](Screenshots/etc-hosts.png)

Набрали в браузере http://www.site2.local/ согласились с рисками и увидели это:

![img.png](Screenshots/site2.png)

### Настраиваем заглушку для неизвестных виртуальных серверов (сайтов)
Чтобы nginx ничего не выдал лишнего, кроме наших 2-х сайтов, делаем заглушку:

  ```bash
    sudo nano /etc/nginx/sites-available/000-catch-all
  ```
Чтобы не забыть, сразу активировали эту конфигурацию:

  ```bash
    sudo ln -s /etc/nginx/sites-available/000-catch-all \
               /etc/nginx/sites-enabled/000-catch-all
  ```
Содержание файла /etc/nginx/sites-available/000-catch-all:

   ```text
    # Неизвестные HTTP-имена
    server {
        listen 80 default_server;
        listen [::]:80 default_server;
    
        server_name _;
    
        return 444;
    }
    
    # Неизвестные HTTPS-имена
    server {
        listen 443 ssl default_server;
        listen [::]:443 ssl default_server;
    
        server_name _;
    
        ssl_certificate     /etc/ssl/certs/default.crt;
        ssl_certificate_key /etc/ssl/private/default.key;
    
        return 444;
    }
   ```

Создали сертификат для https заглушки:

```bash
sudo openssl req -x509 -nodes -newkey rsa:2048 \
  -days 3650 \
  -keyout /etc/ssl/private/default.key \
  -out /etc/ssl/certs/default.crt \
  -subj "/CN=invalid.local" \
  -addext "subjectAltName=DNS:invalid.local"
```
Теперь веб-сервер не отдает ничего лишнего (разумеется после чтения конфигурации и перезапуска nginx)  
   ```bash
    sudo nginx -t
    sudo service nginx reload
   ```

## Проверка 

Редирект на https работает:

![img.png](Screenshots/301MovedPermanently.png)

При флуде запросами упираемся в `429`:

![img.png](Screenshots/429TooManyRequests.png)

`curl` на `/admin` без пароля → `401`:

![img.png](Screenshots/401Unauthorized.png)

# Звездочка 

Начнем с ffuf. ffuf - это это fuzzer для веб-приложений, утилита командной строки. Он берет слова из словаря и подставляет их в URL, отправляя тысячи запросов, чтобы найти скрытые страницы, файлы и директории. С помощью нее можно перебрать множество разных страниц сайта и, если повезет (или не повезет, смотря с какой стороны смотреть) найти то, куда заход рядового пользователя не планировался. Шаблон для использования такой -
```bash
ffuf -u https://example.com/FUZZ -w wordlist.txt
```
В этом примере FUZZ - это плэйсхолдер для окончаний (вроде /admin, /login, /.env), которые ffuf автоматически перебирает за минуты (они находятся в специальном словаре). Плэйсхолдер можно поставить в любое место. ffuf по ответам сервера на запрос той или иной страницы понимает, существует страница или нет и показывает нам этот ответ сервера. Так как запросов перебирается много и при этом очень быстро, в результате при неаккуратном использовании может получиться "404-шторм" или эффект DDoS, распознаваемый средствами защиты (и автоматический бан по IP).

Установим ffuf - 
```bash
sudo apt update
sudo apt install -y ffuf
```
Теперь выберем сайты для сканирования. Попробуем сначала teach-in.ru и artsacademy.ru - это сайт с лекциями по физике и математике и сайт вуза ГАИЖСА им. Репина. Также рассмторим сайт, созданный специально для обучения тестированию безопасности (чтобы уж точно все легально было), - OWASP Juice Shop.

## Дисклеймер (специально для придирчивых)
Авторы не несут ответственности за использование материалов вне
заявленного учебного контекста. Ffuf будет использоваться только в ЛЕГАЛЬНЫХ целях, без ущерба. Все действия производятся только в рамках учебного задания. Еще раз повторим, что будем использовать ffuf ИСКЛЮЧИТЕЛЬНО в образовательных целях, легально, без создания нагрузки на сервера, без DDoS, без подбора паролей, без ущерба для сайта и без использования чего-либо, что будет найдено.

### Что выполняется

- Перебор путей к целевому ресурсу с использованием `ffuf`
  и стандартных публичных словарей (SecLists).
- Методы: только `GET`, `HEAD`, `OPTIONS`.
  Никаких `POST`, `PUT`, `DELETE`, `PATCH`.
- Ограничение частоты запросов: `-rate <N>` (не более N запросов
  в секунду), `-p <задержка>`, чтобы исключить какую-либо существенную
  нагрузку на целевой сервер.
- Никаких попыток эксплуатации найденных путей, чтения содержимого
  за пределами публично доступного, path traversal, LFI/RFI, SQLi,
  bruteforce логинов и паролей.

### Что НЕ выполняется

- Не предпринимаются попытки обхода аутентификации или авторизации.
- Не выполняются атаки класса brute-force, credential stuffing,
  password spraying.
- Не выполняются попытки чтения файлов вне разрешённого корня
  веб-приложения (`/etc/passwd`, `.env`, `.git` и т.п.).
- Не выполняются действия, ведущие к изменению, блокированию,
  удалению или модификации данных на целевом ресурсе.
- Не выполняется нагрузочное тестирование, DoS, DDoS.

### Обработка результатов

- Найденные данные используются исключительно для составления этого
  отчёта.
- Скриншоты и выдержки приводятся минимально необходимые
  и не содержат чувствительных данных (токенов, паролей,
  персональных данных, полного содержимого действующих конфигов).
- По завершении работы артефакты сканирования (сырые логи `ffuf`,
  дампы ответов, промежуточные файлы) удаляются, кроме материалов,
  прямо требуемых для отчёта.

## А теперь - к интересному...

Напишем 
```bash
ffuf -w /opt/SecLists/Discovery/Web-Content/common.txt -u https://teach-in.ru/FUZZ -mc 200,301,302,403 -t 10 -rate 30
```
Разберем эту команду - -w — флаг «wordlist» (список слов). /opt/SecLists/Discovery/Web-Content/common.txt — путь к словарю. Это файл, в котором построчно записаны типичные имена файлов и директорий: admin, backup, .env, config.php, upload, images и т.д. -u — флаг «URL». https://teach-in.ru/FUZZ — целевой адрес. Ключевое слово FUZZ — это placeholder (заполнитель). На его место ffuf подставляет каждое слово из словаря. -mc — флаг «match codes» (коды ответов, которые нужно показывать). 200,301,302,403 — список HTTP-кодов, которые считаются интересными. -t — флаг «threads» (потоки). 10 — количество одновременных запросов. ffuf будет отправлять 10 запросов одновременно. -rate — флаг «rate limit» (ограничение скорости). 30 — 30 запросов в секунду. ffuf не будет отправлять больше 30 запросов в секунду, даже если у него 10 потоков. Это защита от перегрузки сервера и от срабатывания fail2ban. Вот, что получилось -

![img.png](Screenshots/ffufTeach1.png)
Ради интереса попробуем зайти на какой-нибудь адрес, показывающий 200. Например, /media.
![img.png](Screenshots/ffufTeach2.png)
Видим XML документ, явно не предназначеный для юзера вебсайта. Это - публичный листинг MinIO-бакета, список всех изображений, которые используются на сайте. Более того, переходя по ссылкам изображений, их можно увидеть в браузере. Очевидно, в nginx конфиг не прописали запрет на доступ к сайту по этому пути.

Теперь попробуем сайт ГАИЖСА. Вот как выглядит результат ffuf - 
![img.png](Screenshots/ffufAcademy1.png)
Попробуем перейти по тем 200, которые видны. Их относительно немного. Но web-config c 200 выглядит очень заманчиво.
![img.png](Screenshots/ffufAcademy2.png)
Итак, по этому адресу находится web-config в открытом доступе, пусть и старый и закомменченый! Ура, мы попали туда, куда нас не планировали пускать! Теперь попробуем проверить другие 200, но... Сайт больше не доступен. Воображение уже начинает рисовать страшные картины того, как ffuf уронил сервер и как за нами приезжают люди в черном. Но все-же перепроверим свои фантазии. Для этого проверим доступность сайта с другого компьютера - он доступен. Слава богу. Сервер не уронили. Да и не должны были несколько запросов от ffuf его ронять - это как капля в море для любого нормального сервера. Теперь разберемся в том, что творится на нашем девайсе.

![img.png](Screenshots/starBan.png)
Посмотрим, какая конкретно возникает ошибка при соединениии с помощью curl.
![img.png](Screenshots/ffufAcademy4.png)
Итак, здесь видно что сервер refused to connect, следовательно он живой и мы ничего не сломали (ура-ура), но теперь у сервера появились инструкции не общаться с нашим IP-адресом. Сменим IP (в момент скана были на мобильном интернете, включим и выключим авиарежим, чтобы провайдер выдал нам новый IP.) Итак, сайт снова стал доступен. Продолжим исследовать web-config. Так как он закомменчен и еще и в публичном доступе значит, что он, скорее всего, не используется. Это не уязвимость и не проблема. (Хотя из него одного мы узнали, что их бэк написан на php и его местонахождение от C:, что может использоваться для нахождения других уязвимостей, как и тот факт, что они стоят на bitrix (200 на /bitrix), а это открывает целый букет слабостей. Плюсом, если перейти на bitrix, откроется поле для авторизации в админке сайта, а это уже поле для брутфорса.) Так вот, проблема была бы, если бы можно было этот конфиг... раскомментить, например. Или переписать. Проверим это следующей командой.
![img.png](Screenshots/ffufAcademy5.png)
Итак, мы видим, что методов POST нет, значит, использовать доступ напрямую невозможно.

Перейдем теперь к тестированию OWASP Juice Shop.

Для начала запустим сайт (контейнер) через Docker: проверять будем только локальный Juice Shop.

Результат ffuf:
![img.png](Screenshots/ffuf_juice_shop.png)

Посмотрим, что происходит в `\administration`.
![img.png](Screenshots/administration_juice_shop.png)
На страницу не пустили. :( Зато Juice Shop засчитал прохождение челленджа Error Handling - обработку ошибок.

Далее посмотрим, что выведет команда `curl -i http://127.0.0.1:3000/ftp`. 
![img.png](Screenshots/curl_juice_shop.png)
О, это у нас - HTML-страница со списком файлов! Узнаем, что такое `acquisitions.md`.
![img.png](Screenshots/acquisitions_juice_shop.png)
Конфиденциальный документ? Любопытно. Думаю, удалось обнаружить **уязвимость**. 







