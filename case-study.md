# Case-study оптимизации

## Актуальная проблема
В нашем проекте возникла серьёзная проблема.

Необходимо было обработать файл с данными, чуть больше ста мегабайт.

У нас уже была программа на `ruby`, которая умела делать нужную обработку.

Она успешно работала на файлах размером пару мегабайт, но для большого файла она работала слишком долго, и не было 
понятно, закончит ли она вообще работу за какое-то разумное время.

Я решил исправить эту проблему, оптимизировав эту программу.

## Формирование метрики
Для того, чтобы понимать, дают ли мои изменения положительный эффект на быстродействие программы я буду использовать
такую метрику, как **время обработки файла**. 

## Гарантия корректности работы оптимизированной программы
Программа поставлялась с тестом. Выполнение этого теста в фидбек-лупе позволяет не допустить изменения логики программы 
при оптимизации.

## Feedback-Loop и моя подготовка к нему
Для того, чтобы иметь возможность быстро проверять гипотезы я выстроил эффективный `feedback-loop`, который позволил мне 
получать обратную связь по эффективности сделанных изменений за *~21 секунду*.

Перед началом цикла оптимизации решил подготовить весь проект к какому-то более-менее приличному виду, который мне позволит в комфорте проводить оптимизацию,
ну и естественно подумал, что оптимизированным решением было бы посмотреть статьи на тему профайлинга и тех инструментов, 
которые я буду использовать как для поиска хороших практик, так и для может быть дополнительной инфы, кроме той, которую 
рассказывал сам Алексей на курсе. 

Прочитал документации библиотек, представленных в дашборде во вкладке CPU. Очень заинтересовался репозиторием fast-ruby.
Немножко порыскав во всемирной паутине нашел интересную статью на хабре https://habr.com/ru/post/561258/, где в целом задача 
примерно такая же, как у меня сейчас, что безусловно мне пригодилось как в подготовке среды, так и к общей истории с оптимизацией.

Далее последовали следующие шаги подготовки проекта к циклам оптимизации и последующей публикации этого дз для других людей:
1. Так как мы используем зависимости для профилирования, то создаю Gemfile с указанием версий как гемов, так и Ruby.
2. Создаю .gitignore
3. Дальше потихоньку начинаю погружаться в требования задания, вспоминаю, что очень важным фактором для оптимизации является проведение асимптотического анализа, а значит понадобится несколько исходных файлов текста, которые позволят найти асимптоту. Для всего этого нам понадобится дополнительный аргумент **filename** к методу work.
4. После беглого осмотра файла task-1.rb заметил наличие тестов прямо в этом же файле. Естественно вынес их в другой файл test/task_1_test.rb
5. Так как мы хотим в начале найти асимптоту, то решил создать 10 файлов с шагом в 2000 строк.

``` 
# generate data
lines = [2000, 4000, 6000, 8000, 10000, 12000, 14000, 16000, 18000, 20000]

lines.each do |line|
head -n #{line} data/data_large.txt > data/data-#{line}-lines.txt
end
```
6. Создаю файл `profilers/benchmark_data.rb` для подсчета времени обработки исходников с использованием метода `Benchmark.realtime`. Получаю результаты:

``` 
$ ruby profilers/benchmark_data.rb
   2000 Completed in 0.082 ms
   4000 Completed in 0.271 ms
   6000 Completed in 0.582 ms
   8000 Completed in 1.007 ms
   10000 Completed in 1.67 ms
   12000 Completed in 2.389 ms
   14000 Completed in 3.209 ms
   16000 Completed in 4.452 ms
   18000 Completed in 5.424 ms
   20000 Completed in 6.58 ms
``` 
7. C помощью plotly.com построил график с этими значениями. Получилось что-то похожее на `1.6 * x^2`, то есть линейность отсутствует и при большем количестве строк во входных данных есть серьезные обоснования таки не дождаться долгожданного списка с результатами..
   ![alt text](https://i.imgur.com/KEf67gj.png)
8. Добавляю параметр для метода work `disable_gc` со значением `true` по умолчанию, чтобы уменьшить разброс времени выполнения
9. Теперь пробую написать небольшой тестик для того, чтобы недопустить более худшего времени выполнения и уже наконец-то приступать к самой оптимизации. Лезу в гитхаб `rspec-benchmark` и из общих практик составляю вроде что-то рабочее. В качестве эталона для теста беру 8000 строк с не более 1.5 секунды выполнения.

```      
expect {
         work('data/data_8000.txt')
       }.to perform_under(1500).ms.warmup(2).times.sample(5).times
```
10. Изначально планировал во всю использовать встроенный в RubyMine rbspy, но по какой-то причине он у меня отвалился и кнопка активации была неактивная, при том, что через консоль все отлично вызывалось. Повозившись еще немного решил все-таки вернуться к `ruby-prof` с тремя разными типами данных. Плюс дополнительно для визуализации использовал `flamegraph`
11. Ну и последним пунктом перед циклом настраиваю себе в IDE две конфигурации: под запуск тестов, и под профилировщики, что позволит очень быстро проходить итерации.

## Вникаем в детали системы, чтобы найти главные точки роста
### Ваша находка №1
- `Ruby prof` довольно таки прямо сказал, что проблема в `Array#select`, берущий на себя 89% времени обработки.  А именно: 
```
    user_sessions = sessions.select { |session| session['user_id'] == user['id'] }
```
- Решил применить принцип мемоизации. Все сессии пользователя теперь сохраняем в хэше и потом уже его используем в цикле.
- Асимптотика пришла к почти линейному состоянию, а время выполнение существенно уменьшилось.
  ```
  20000 Completed in 0.573 ms
  ```
- Успешный запуск обоих тестов, проверяем, что точка роста поменялась на `Array#each`, меняем тест защиты от регрессии производительности, коммитим. В целом, уже видно, что процесс с конфигурациями запусков в IDE удобен и вполне подходит под подобный тип цикл.

### Ваша находка №2
- `Ruby prof` (тут я понял, что мой временный любимец все-таки Graph) выявил точку роста  в `Array#each (Array#all?)`. 
- Очевидно, что проблема в том, что идет сначала сохранение в массивы `users` и `sessions` во время `file_lines.each`, а потом уже запуск излишних циклов перебора для каждого отдельно. По идее, там надо все очень сильно рефакторить и переносить всю логику в `file_lines.each`, но тут я вспомнил про первую мантру (а не про свою лень, правда-правда) и решил заняться куском кода, отвечающего за подсчет количества уникальных браузера, ну и все-таки не удержался и чуть-чуть порефакторил код.
- Метрика улучшилась, Array#all ушел из пика
```
  20000 Completed in 0.495 ms
```
- Успешный запуск обоих тестов, проверяем, что точка роста поменялась на caller `collect_stats_from_users` и его callees `Array#each`, меняем тест защиты от регрессии производительности, коммитим.

### Ваша находка №3
- По отчетам вижу, что точка роста - это caller `collect_stats_from_users`. Переписал этот часть кода, буст производительности стал виден.
```
20000 Completed in 0.213 ms
40000 Completed in 0.503 ms
60000 Completed in 0.82 ms
80000 Completed in 1.028 ms
100000 Completed in 1.325 ms
```
- Точка роста поменялась на `Date#iso8601` и его caller `Date.parse`

### Ваша находка №4
- На этом моменте решил закругляться и начал пытаться смотреть, а что по вхождению метрики в бюджет при попытке работы с `data_large.txt`
```
100000 Completed in 1.421 ms
200000 Completed in 3.073 ms
400000 Completed in 10.805 ms
600000 Completed in 26.066 ms
```
- Результаты оказались не очень и при большом количестве строк асимптота превращалась из более-менее похожей на линейную на малых значениях на ту, которая нас вообще не устраивает, ибо опять появился риск не дожить до результатов.
- Пошел изучить формат iso8601 и входные даты, понял подвох задачки, улыбнулся и убрал метод `parse`. Опять использовал мемоизацию с `browsers`, чтобы избавиться от лишних `map`, ну и отрефакторил вырвиглазные хэши со строками. Результаты теперь стали выглядеть более привлекательно:
```
  100000 Completed in 0.958 ms
  200000 Completed in 2.213 ms
  400000 Completed in 6.828 ms
  600000 Completed in 13.153 ms
```

- Точка роста поменялась на `Date#iso8601` на `collect_stats_from_users`
### Ваша находка №5

- В общем, таки пришлось оптимизировать `collect_stats_from_users`, ну и в целом результаты опять же улучшить в два раза.
```
    100000 Completed in 0.423 ms
    200000 Completed in 0.901 ms
    400000 Completed in 1.831 ms
    600000 Completed in 3.083 ms
```

- На этом моменте, я воодушевился, подрубил турбобустик у моего райзена 5800h (шучу) и достиг бюджета с результатом обработки `data_large`: 

```
Completed in 21.047 ms
```
C отключенным cборщиком получилось вообще за `12.732 ms`


## Результаты
В результате проделанной оптимизации наконец удалось обработать файл с данными.
Удалось улучшить метрику системы с бесконечно долгого времени выполнения до ~21 секунды и уложиться в заданный бюджет.

Домашнее задание показалось крайне интересным, попрактиковался со всеми профилировщиками и видами вывода их результатов, поизучал практики, ну и наверное самое главное - это выстроил себе в голове более-менее (явно еще можно все это улучшать) быстрый (пара секунд на запуск профилировщиков и тестов) цикл оптимизации.

## Защита от регрессии производительности
Для защиты от потери достигнутого прогресса при дальнейших изменениях программы был написан rspec-тест, который при каждой итерации подводился к уже улучшенному времени, что позволяло проводить постоянную защиту от регресса уже оптимизированного времени. Явно утащу подобную практику уже в рабочий проект подобную практику, так как эффективность очень круто себя показала.

