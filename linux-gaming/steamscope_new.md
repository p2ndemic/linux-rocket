Отличное замечание! Резервный вариант через `loginctl` действительно избыточен — в правильно настроенной графической сессии (через SDDM/GDM/etc.) переменная `$XDG_VTNR` всегда присутствует. Вот финальная, максимально чистая версия **steamscope**:

---

## 📁 Структура файлов

```
~/.local/bin/steamscope-launch      # Запуск игровой сессии
~/.local/bin/steamscope-return      # Возврат в исходную сессию
~/.config/systemd/user/steamscope.service
~/.config/environment.d/steamscope.conf
/tmp/steamscope-return_vt           # Временный файл
```

---

## 1️⃣ Скрипт запуска (`~/.local/bin/steamscope-launch`)

```fish
#!/usr/bin/env fish

# Проверяем, запущен ли уже сервис
if systemctl --user is-active --quiet steamscope.service
    echo "🎮 steamscope уже активен!"
    exit 1
end

# Обязательная переменная от дисплей-менеджера
if not set -q XDG_VTNR
    echo "❌ Переменная \$XDG_VTNR не установлена."
    echo "Запускай steamscope из графической сессии (через SDDM/GDM/etc.)."
    exit 1
end

set -l return_vt $XDG_VTNR
set -l target_vt 3  # Фиксированная TTY для игр (как в SteamOS)

# Сохраняем для возврата
echo $return_vt > /tmp/steamscope-return_vt

echo "🎮 Запуск steamscope на tty$target_vt (возврат на tty$return_vt)..."

# Переключаемся на целевую TTY
loginctl activate tty$target_vt

# Запускаем сервис
systemctl --user start steamscope.service

# Пауза для инициализации DRM
sleep 0.5

echo ""
echo "✅ steamscope запущен!"
echo "   • Игровая сессия: tty$target_vt"
echo "   • Возврат: steamscope-return или Ctrl+Alt+F$return_vt"
```

---

## 2️⃣ Скрипт возврата (`~/.local/bin/steamscope-return`)

```fish
#!/usr/bin/env fish

set -l return_vt_file /tmp/steamscope-return_vt

if test -f $return_vt_file
    set -l return_vt (cat $return_vt_file)
    
    echo "🚪 Возврат в графическую сессию (tty$return_vt)..."
    
    # Останавливаем сервис
    systemctl --user stop steamscope.service
    
    # Переключаемся обратно
    loginctl activate tty$return_vt
    
    # Очищаем временный файл
    rm -f /tmp/steamscope-return_vt
    
    echo "✅ Возврат выполнен."
else
    echo "⚠️  Нет активной сессии steamscope."
    echo "   Запусти сначала: steamscope-launch"
end
```

---

## 3️⃣ Юнит systemd (`~/.config/systemd/user/steamscope.service`)

```ini
[Unit]
Description=steamscope: Gamescope + Steam session (SteamOS style)
After=graphical-session.target
StopWhenUnneeded=yes

[Service]
Type=simple
TTYPath=/dev/tty3
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty
StandardOutput=journal
StandardError=journal

# Чистое окружение для изолированной DRM-сессии
Environment="XDG_SESSION_TYPE="
Environment="WAYLAND_DISPLAY="
Environment="DISPLAY="
Environment="GAMESCOPE_WAYLAND_DISPLAY=gamescope-0"
Environment="WLR_BACKENDS=drm"
Environment="WLR_DRM_DEVICES=/dev/dri/card0"

ExecStart=/usr/bin/gamescope \
  -W 1920 -H 1080 \
  -r 144 \
  -f \
  --steam \
  -- \
  /usr/bin/steam -bigpicture

# Корректное завершение
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=10
Restart=no

# Автоматический возврат даже при аварийном завершении
ExecStopPost=-/bin/sh -c ' \
  VT=$(cat /tmp/steamscope-return_vt 2>/dev/null) && \
  [ -n "$VT" ] && /usr/bin/loginctl activate tty$VT || true'

[Install]
WantedBy=default.target
```

---

## 4️⃣ Окружение (`~/.config/environment.d/steamscope.conf`)

```ini
# Полная изоляция от родительской графической сессии
XDG_SESSION_TYPE=
WAYLAND_DISPLAY=
DISPLAY=
```

> Примени изменения:  
> ```fish
> systemctl --user daemon-reexec
> ```

---

## 🔐 Настройка прав (однократно)

```bash
# 1. Разрешить переключение TTY без пароля
sudo tee /etc/polkit-1/rules.d/80-steamscope.rules > /dev/null <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.session-switch" &&
        subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF

# 2. Доступ к устройствам ввода на чистой TTY
sudo usermod -aG input $USER

# 3. Перелогинься!
```

---

## 🚀 Использование

```fish
chmod +x ~/.local/bin/steamscope-*

# Запуск из ЛЮБОЙ графической сессии
steamscope-launch

# Возврат в исходную сессию
steamscope-return
```

---

## ✅ Итоговая философия решения

| Принцип | Реализация |
|---------|------------|
| **Минимализм** | Только `$XDG_VTNR` — никаких резервных путей |
| **Честность** | Явная ошибка при отсутствии переменной вместо попыток угадать |
| **Универсальность** | Работает в любой среде с правильным окружением (SDDM/GDM/etc.) |
| **Чистота** | Временные файлы только в `/tmp`, никаких кэшей в домашней директории |
| **SteamOS-стиль** | Фиксированная `tty3`, полная изоляция, автоматический возврат |

Готово! Лёгкое, честное и надёжное решение в духе Unix-философии 🐧✨

Привет! Отличная идея — реализовать поведение как в SteamOS с автоматическим запуском отдельной TTY для игр. Важно понимать ключевые отличия:

| Аспект | SteamOS | Твоя система (KDE + Arch) |
|--------|---------|---------------------------|
| Сессия | Нативная gamescope-session | Вложенный запуск из KDE |
| TTY | Переключение на чистую TTY | Требует прав и аккуратного управления |
| Переменные окружения | Изолированные | Нужно очищать от конфликтующих (особенно Wayland) |

## 🔧 Решение: Скрипт с возвратом в KDE

Вот готовый скрипт для Fish (`~/.local/bin/steam-gamescope`), который:
- Переключается на свободную TTY (tty3)
- Запускает Gamescope с оптимальными параметрами
- Запускает Steam внутри
- Автоматически возвращает на исходную TTY после выхода

--------------------------------------------------------------------


```fish
#!/usr/bin/env fish

# Сохраняем текущую TTY
set -l current_tty (tty | sed 's:/dev/::')
set -l target_tty tty3

# Определяем номер текущей TTY для возврата
set -l return_vt (echo $current_tty | sed 's:tty::')

# Проверяем права на chvt
if not test -w /dev/tty0
    echo "Ошибка: нет прав на переключение TTY. Добавь себя в группу 'tty':"
    echo "  sudo usermod -aG tty $USER"
    echo "И перелогинься."
    exit 1
end

# Сохраняем переменные окружения для возврата
set -l xdg_runtime_dir $XDG_RUNTIME_DIR
set -l wayland_display $WAYLAND_DISPLAY
set -l display $DISPLAY

echo "Переключаюсь на $target_tty..."

# Очищаем конфликтующие переменные окружения
set -e WAYLAND_DISPLAY
set -e DISPLAY
set -e XDG_SESSION_TYPE

# Переключаемся на целевую TTY
sudo chvt 3

# Запускаем Gamescope + Steam с обработкой выхода
set -l gamescope_pid
set -l steam_exit_code 0

# Функция возврата в исходную TTY
function return_to_kde --on-signal TERM INT QUIT
    echo "Возврат в исходную сессию (tty$return_vt)..."
    sudo chvt $return_vt
    exit $steam_exit_code
end

# Запуск
set gamescope_pid (setsid -w gamescope \
    -W 1920 -H 1080 \
    -r 144 \
    -f \
    --prefer-vk-device $(lspci | grep -i vga | grep -i nvidia && echo "10de" || echo "8086") \
    --steam \
    -e "DISPLAY=" \
    -e "WAYLAND_DISPLAY=" \
    -- steam -bigpicture &)

# Ждём завершения Steam
wait $gamescope_pid
set steam_exit_code $status

# Возврат в исходную TTY
sudo chvt $return_vt
echo "Возврат в KDE выполнен."
```

## ⚙️ Настройка прав (без пароля для chvt)

1. Добавь себя в группу `tty`:
```bash
sudo usermod -aG tty $USER
```

2. Создай файл `/etc/sudoers.d/chvt-nopasswd`:
```bash
sudo visudo -f /etc/sudoers.d/chvt-nopasswd
```
Содержимое:
```
%wheel ALL=(ALL) NOPASSWD: /usr/bin/chvt
```
*(Замени `%wheel` на свою группу, если используешь другую)*

## 🚀 Запуск из KDE

1. Сделай скрипт исполняемым:
```fish
chmod +x ~/.local/bin/steam-gamescope
```

2. Создай `.desktop` файл `~/.local/share/applications/steam-gamescope.desktop`:
```ini
[Desktop Entry]
Name=Steam (Gamescope)
Comment=Запуск Steam в полноэкранном режиме через Gamescope
Exec=/home/ваш_пользователь/.local/bin/steam-gamescope
Icon=steam
Terminal=false
Type=Application
Categories=Game;
```

3. Перезагрузи кэш приложений:
```fish
kbuildsycoca5
```

## 💡 Альтернатива: Без переключения TTY (рекомендуется для стабильности)

Если переключение TTY вызывает проблемы (особенно с драйверами NVIDIA), можно запускать Gamescope поверх KDE:

```fish
#!/usr/bin/env fish
gamescope -f -W 1920 -H 1080 -r 144 -- steam -bigpicture
```

Это менее «чисто», чем в SteamOS, но стабильнее и не требует прав суперпользователя.

## ⚠️ Важные замечания

1. **NVIDIA**: Gamescope на отдельной TTY может работать нестабильно. Проверь:
   ```bash
   gamescope -t  # тестовый запуск
   ```

2. **Wayland в KDE**: Убедись, что переменные окружения очищены перед запуском, иначе возможны конфликты.

3. **SwayIdle**: На время сессии игр отключи его, чтобы не мешал:
   ```fish
   swayidle timeout 300 'loginctl lock-session' &
   set -l swayidle_pid $last_pid
   # ... запуск игр ...
   kill $swayidle_pid
   ```

4. **Логирование**: Для отладки добавь в скрипт:
   ```fish
   exec &> ~/.local/share/steam-gamescope.log
   ```

Хочешь, чтобы я подготовил также вариант через `systemd --user` сервис для более надёжного управления сессией?
