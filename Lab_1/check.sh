#!/bin/bash

url="http://notes.app"
printf "Проверяем редирект с http на https.\n"
printf "Выполняю: curl -I %s\n" "$url"
printf "Результат:\n"
curl -I "$url"


url="https://notes.app/api/backend_health"
printf "Проверяем работу двух инстансов бэкенда. Для завершения проверки нажмите клавишу q\n"
was_break=1
while true; do
    printf "\nВыполняю: curl -ks %s\n" "$url"
    printf "Результат:\n"
    curl -ks "$url"
    for ((i = 0; i < 25; i++)); do
        if read -r -n 1 -s -t 0.1 key &&
		[[ "$key" == "q" ]]; then
	        was_break=0
		break
	fi;
    done
    if [[ "$was_break" -eq 0 ]]; then
        break
    fi
done

url="https://notes.app/admin"
printf "\nПроверяем curl на /admin без пароля.\n"
printf "Выполняю: curl -kL %s\n" "$url"
printf "Результат:\n"
curl -kL "$url"


printf "\n"
url="https://notes.app/api/notes"
printf "Проверяем реакцию сервиса Наши заметки на флуд запросами.\n"
read -p "Введите количество запросов: " req_count
((req_count += 1))
for ((i=1; i < $req_count; i++)); do
    printf "\nВыполняю запрос №$i: curl -kI %s\n" "$url"
    printf "Результат:\n"
    curl -kI "$url"
done

url="http://127.0.0.1/"
printf "\nПроверяем  ● запрос с чужим Host → отдаётся только его проект, не соседний.\n"
printf "Выполняю: curl -kL %s\n" "$url"
printf "Результат:\n"
curl -I "$url"

url="https://site2.local/test"
printf "\nПроверяем ● запрос несуществующей страницы → ваша 404.\n"
printf "Выполняю: curl -kL %s\n" "$url"
printf "Результат:\n"
curl -kL "$url"

printf "\nПытаемся запросить в firefox несуществующую страницу и отобразить нашу 404.html\n"
firefox --new-window "$url" >/dev/null 2>&1 &


