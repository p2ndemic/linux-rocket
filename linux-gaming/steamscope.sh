#!/bin/bash
set -Euo pipefail

# ========== КОНФИГУРАЦИЯ ==========
APP_NAME="steamscope"
CONFIG_DIR="$HOME/.config/steamscope"
CONFIG_FILE="$CONFIG_DIR/steamscope.conf"
BIN_DIR="$HOME/.local/bin"
ENTER_BIN="$BIN_DIR/enter-steamscope"
LEAVE_BIN="$BIN_DIR/leave-steamscope"
STATE_DIR="$HOME/.cache/steamscope"
SESSION_FILE="$STATE_DIR/session.pid"

# ========== ФУНКЦИИ ДЛЯ ВЫВОДА ==========
info() { echo "[*] $*"; }
err() { echo "[!] $*" >&2; }

die() {
  local msg="$1"; local code="${2:-1}"
  err "FATAL: $msg"
  exit "$code"
}

# ========== ФУНКЦИЯ ОТКАТА ==========
rollback_changes() {
  [ -f "$ENTER_BIN" ] && rm -f "$ENTER_BIN"
  [ -f "$LEAVE_BIN" ] && rm -f "$LEAVE_BIN"
}

trap rollback_changes ERR

# ========== ПРОВЕРКА СРЕДЫ ==========
validate_environment() {
  command -v lspci >/dev/null || die "Требуется pciutils (установите: sudo pacman -S pciutils)"
}

# ========== ПРОВЕРКА ПАКЕТА ==========
check_package() {
  pacman -Qi "$1" &>/dev/null 2>/dev/null
}

# ========== ПРОВЕРКА ЗАВИСИМОСТЕЙ STEAM ==========
check_steam_dependencies() {
  info "Проверка зависимостей Steam..."
  
  # Основные зависимости Steam
  local -a core_deps=(
    "steam"                    # Steam клиент
    "lib32-vulkan-icd-loader"  # 32-битный Vulkan loader
    "vulkan-icd-loader"        # 64-битный Vulkan loader
    "lib32-mesa"               # 32-битная Mesa
    "mesa"                     # 64-битная Mesa
    "mesa-utils"               # Утилиты Mesa
    "lib32-glibc"              # 32-битная glibc
    "lib32-gcc-libs"           # 32-битные библиотеки GCC
    "lib32-libx11"             # 32-битный X11
    "lib32-libxss"             # 32-битный X screensaver
    "lib32-alsa-plugins"       # 32-битный ALSA
    "lib32-libpulse"           # 32-битный PulseAudio
    "lib32-openal"             # 32-битный OpenAL
    "lib32-nss"                # 32-битный NSS
    "lib32-libcups"            # 32-битный CUPS
    "lib32-sdl2"               # 32-битный SDL2
    "lib32-freetype2"          # 32-битные шрифты
    "lib32-fontconfig"         # 32-битная конфигурация шрифтов
    "ttf-liberation"           # Шрифты Liberation
    "xdg-user-dirs"            # Пользовательские директории
  )
  
  # Определяем GPU для установки правильных драйверов
  local gpu_vendor
  gpu_vendor=$(lspci 2>/dev/null | grep -iE 'vga|3d|display' || echo "")
  
  local has_nvidia=false has_amd=false has_intel=false
  
  echo "$gpu_vendor" | grep -iq nvidia && has_nvidia=true
  echo "$gpu_vendor" | grep -iqE 'amd|radeon|advanced micro' && has_amd=true
  echo "$gpu_vendor" | grep -iq intel && has_intel=true
  
  local -a gpu_deps=()
  
  # NVIDIA драйверы
  if $has_nvidia; then
    info "Обнаружена NVIDIA GPU"
    gpu_deps+=(
      "nvidia-utils"
      "lib32-nvidia-utils"
      "nvidia-settings"
      "libva-nvidia-driver"
    )
  fi
  
  # AMD драйверы
  if $has_amd; then
    info "Обнаружена AMD GPU"
    gpu_deps+=(
      "vulkan-radeon"
      "lib32-vulkan-radeon"
      "libva-mesa-driver"
      "lib32-libva-mesa-driver"
    )
  fi
  
  # Intel драйверы (для вашего i5-1240p с Iris Xe)
  if $has_intel; then
    info "Обнаружена Intel GPU (Iris Xe)"
    gpu_deps+=(
      "vulkan-intel"
      "lib32-vulkan-intel"
      "intel-media-driver"
      "libva-intel-driver"
      "lib32-libva-intel-driver"
      "intel-compute-runtime"
    )
  fi
  
  # Общие Vulkan инструменты
  gpu_deps+=(
    "vulkan-tools"
    "vulkan-mesa-layers"
  )
  
  # Рекомендуемые зависимости
  local -a recommended_deps=(
    "gamescope"           # Композитор для игр
    "mangohud"            # Оверлей производительности
    "lib32-mangohud"      # 32-битный MangoHud
    "protontricks"        # Помощник для Proton
    "protonplus"          # Менеджер версий Proton
    "gum"                 # TUI утилита для скриптов
    "python"              # Python для скриптов
    "curl"                # Для загрузки файлов
    "pciutils"            # Для определения оборудования
    "bc"                  # Для математических операций
  )
  
  # Проверяем основные зависимости
  local -a missing_deps=()
  local -a optional_deps=()
  
  info "Проверка основных зависимостей Steam..."
  for dep in "${core_deps[@]}"; do
    check_package "$dep" || missing_deps+=("$dep")
  done
  
  # Проверяем GPU зависимости
  info "Проверка GPU зависимостей..."
  for dep in "${gpu_deps[@]}"; do
    check_package "$dep" || missing_deps+=("$dep")
  done
  
  # Проверяем рекомендуемые зависимости
  info "Проверка рекомендуемых зависимостей..."
  for dep in "${recommended_deps[@]}"; do
    check_package "$dep" || optional_deps+=("$dep")
  done
  
  # Выводим результаты
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  РЕЗУЛЬТАТЫ ПРОВЕРКИ ЗАВИСИМОСТЕЙ"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  
  # Обязательные зависимости
  if ((${#missing_deps[@]})); then
    echo "  ОБЯЗАТЕЛЬНЫЕ ПАКЕТЫ (${#missing_deps[@]}):"
    for dep in "${missing_deps[@]}"; do
      echo "    • $dep"
    done
    echo ""
    
    read -p "Установить недостающие пакеты? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      info "Установка недостающих зависимостей..."
      sudo pacman -S --needed "${missing_deps[@]}" || die "Не удалось установить зависимости"
      info "Зависимости установлены успешно"
    else
      die "Нельзя продолжить без обязательных зависимостей"
    fi
  else
    info "Все обязательные зависимости установлены!"
  fi
  
  # Рекомендуемые зависимости
  echo ""
  if ((${#optional_deps[@]})); then
    echo "  РЕКОМЕНДУЕМЫЕ ПАКЕТЫ (${#optional_deps[@]}):"
    for dep in "${optional_deps[@]}"; do
      echo "    • $dep"
    done
    echo ""
    
    read -p "Установить рекомендуемые пакеты? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      info "Установка рекомендуемых пакетов..."
      sudo pacman -S --needed --noconfirm "${optional_deps[@]}" || info "Некоторые пакеты не установились"
    fi
  else
    info "Все рекомендуемые пакеты установлены!"
  fi
  
  echo ""
  echo "════════════════════════════════════════════════════════════════"
}

# ========== ПРОВЕРКА КОНФИГУРАЦИИ STEAM ==========
check_steam_config() {
  info "Проверка конфигурации Steam..."
  
  # Проверяем группы пользователя
  local missing_groups=()
  
  if ! groups | grep -qw 'video'; then
    missing_groups+=("video")
  fi
  
  if ! groups | grep -qw 'input'; then
    missing_groups+=("input")
  fi
  
  if ((${#missing_groups[@]})); then
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  НАСТРОЙКА ПРАВ ПОЛЬЗОВАТЕЛЯ"
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Ваш пользователь должен быть добавлен в группы:"
    echo ""
    for group in "${missing_groups[@]}"; do
      case "$group" in
        video) echo "    • video  - Доступ к GPU" ;;
        input) echo "    • input  - Поддержка контроллеров" ;;
      esac
    done
    echo ""
    echo "  Без этих групп могут быть проблемы с:"
    echo "    - Доступом к видеокарте"
    echo "    - Работой контроллеров и геймпадов"
    echo ""
    echo "  ВНИМАНИЕ: После добавления в группы необходимо"
    echo "            выйти из системы и войти заново."
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    
    read -p "Добавить пользователя в группы ${missing_groups[*]}? [Y/n]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      local groups_to_add=$(IFS=,; echo "${missing_groups[*]}")
      info "Добавление пользователя в группы: $groups_to_add"
      if sudo usermod -aG "$groups_to_add" "$USER"; then
        info "Пользователь добавлен в группы: $groups_to_add"
        NEEDS_RELOGIN=1
      else
        err "Не удалось добавить пользователя в группы"
        info "Можно добавить вручную: sudo usermod -aG $groups_to_add $USER"
      fi
    else
      info "Пропускаем добавление в группы"
    fi
  else
    info "Пользователь уже в группах video и input"
  fi
  
  # Проверяем директории Steam
  [ -d "$HOME/.steam" ] && info "Steam директория найдена: ~/.steam"
  [ -d "$HOME/.local/share/Steam" ] && info "Steam данные найдены: ~/.local/share/Steam"
}

# ========== НАСТРОЙКА CAPABILITY ДЛЯ GAMESCOPE ==========
setup_gamescope_capabilities() {
  info "Настройка прав для Gamescope..."
  
  if ! command -v gamescope >/dev/null 2>&1; then
    info "Gamescope не установлен, пропускаем настройку прав"
    return 0
  fi
  
  # Проверяем уже установленные права
  if getcap "$(command -v gamescope)" 2>/dev/null | grep -q 'cap_sys_nice'; then
    info "Gamescope уже имеет cap_sys_nice capability"
    return 0
  fi
  
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  НАСТРОЙКА ПРАВ GAMESCOPE"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "  Для снижения задержек рекомендуется предоставить gamescope"
  echo "  возможность работать с реальным временем (cap_sys_nice)."
  echo ""
  echo "  Это позволяет gamescope:"
  echo "  • Запускаться с приоритетом реального времени (--rt)"
  echo "  • Уменьшать задержки и улучшать стабильность кадров"
  echo ""
  echo "  Примечание: Эта возможность будет предоставлена ВСЕМ"
  echo "  пользователям, которые могут запускать gamescope."
  echo ""
  echo "  Можно удалить позже командой:"
  echo "  sudo setcap -r $(command -v gamescope)"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  
  read -p "Предоставить cap_sys_nice для gamescope? [y/N]: " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo setcap 'cap_sys_nice+ep' "$(command -v gamescope)" || info "Не удалось установить capability"
    info "Права для gamescope настроены"
  else
    info "Пропускаем настройку прав для gamescope"
  fi
}

# ========== СОЗДАНИЕ КОНФИГУРАЦИОННОГО ФАЙЛА ==========
create_config_file() {
  info "Создание конфигурационного файла..."
  
  mkdir -p "$CONFIG_DIR" || die "Не удалось создать директорию конфига"
  
  if [ -f "$CONFIG_FILE" ]; then
    info "Конфигурационный файл уже существует: $CONFIG_FILE"
    echo ""
    read -p "Перезаписать конфигурационный файл? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      info "Пропускаем создание конфигурационного файла"
      return 0
    fi
  fi
  
  cat > "$CONFIG_FILE" <<CONFIG
# Конфигурация Steamscope
# Файл: ~/.config/steamscope/steamscope.conf

# ========== НАСТРОЙКИ GAMESCOPE ==========

# Нативное разрешение (выходное)
NATIVE_WIDTH="2560"
NATIVE_HEIGHT="1600"

# Разрешение рендеринга (игровое)
# Доступные опции: 2560x1600, 1680x1050, 1280x800
RENDER_WIDTH="1680"
RENDER_HEIGHT="1050"

# Частота обновления (Hz)
REFRESH_RATE="120"

# Режим запуска Steam (bigpicture или gamepadui)
STEAM_LAUNCH_MODE="bigpicture"

# Дополнительные аргументы Gamescope
# -f  : полноэкранный режим
# -e  : выходить при завершении дочернего процесса
# --force-grab-cursor : фиксировать курсор в играх
GAMESCOPE_ARGS="-f -e --force-grab-cursor"

# Режим реального времени для Gamescope (--rt)
# Включить только если предоставлена cap_sys_nice capability
GAMESCOPE_REALTIME="true"

# ========== НАСТРОЙКИ ОПТИМИЗАЦИИ ==========

# Включить falcond (автоматическая оптимизация игр)
# Falcond будет использовать свой конфиг: /etc/falcond/config.conf
# и профили игр из /usr/share/falcond/profiles/
FALCOND_ENABLED="true"

# Включить tuned (оптимизация системы)
# Профиль для игр: performance (создайте свой при необходимости)
TUNED_ENABLED="true"
TUNED_PERFORMANCE_PROFILE="performance"
TUNED_DEFAULT_PROFILE="balanced"

# ========== НАСТРОЙКИ MANGOHUD ==========

# Включить MangoHud (оверлей производительности)
MANGOHUD_ENABLED="true"
MANGOHUD_CONFIG="fps,position=top-left,font_size=24,offset_x=10,offset_y=10"

# ========== ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ ==========

# Экспортировать переменные окружения для исправления проблем
export LD_PRELOAD=""
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export __GL_SYNC_TO_VBLANK=0

# Оптимизация для Intel Iris Xe
export ANV_GPL=1
export mesa_glthread=true

# Оптимизация для Wayland
export WLR_DRM_NO_ATOMIC=1
export WLR_RENDERER_ALLOW_SOFTWARE=1

# ========== КОНФИГУРАЦИЯ ДЛЯ ВАШЕГО НОУТБУКА ==========
# Intel Core i5 1240p с iGPU Iris XE
# 8GB RAM, 256GB NVME
# 16" 2560x1600@120Hz (2.0 Scale)
# Терминал: foot
# Оконные менеджеры: labwc / sway

# Рекомендуемая конфигурация falcond (/etc/falcond/config.conf):
# enable_performance_mode = true
# scx_sched = none
# scx_sched_props = default
# vcache_mode = none
# profile_mode = none

# Рекомендуемая конфигурация tuned:
# sudo tuned-adm profile performance
CONFIG

  info "Создан конфигурационный файл: $CONFIG_FILE"
  info "Отредактируйте его под свои нужды"
}

# ========== СОЗДАНИЕ СКРИПТОВ ЗАПУСКА ==========
create_launch_scripts() {
  info "Создание скриптов запуска..."
  
  # Создаем директорию для бинарников если нужно
  mkdir -p "$BIN_DIR" 2>/dev/null || true
  
  # Создаем скрипт запуска (упрощенная версия)
  cat > "$ENTER_BIN" <<'ENTER_EOF'
#!/bin/bash
set -Euo pipefail

# Загружаем конфигурацию
CONFIG_FILE="$HOME/.config/steamscope/steamscope.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Конфигурационный файл не найден: $CONFIG_FILE"
  echo "Создайте его или запустите установку steamscope"
  exit 1
fi

# Создаем директорию для состояния
STATE_DIR="$HOME/.cache/steamscope"
SESSION_FILE="$STATE_DIR/session.pid"
mkdir -p "$STATE_DIR"

# Загружаем конфиг
source "$CONFIG_FILE"

# Устанавливаем значения по умолчанию если не заданы
: "${STEAM_LAUNCH_MODE:=bigpicture}"
: "${NATIVE_WIDTH:=2560}"
: "${NATIVE_HEIGHT:=1600}"
: "${RENDER_WIDTH:=1680}"
: "${RENDER_HEIGHT:=1050}"
: "${REFRESH_RATE:=120}"
: "${GAMESCOPE_ARGS:=-f -e --force-grab-cursor}"
: "${GAMESCOPE_REALTIME:=true}"
: "${FALCOND_ENABLED:=false}"
: "${TUNED_ENABLED:=false}"
: "${TUNED_PERFORMANCE_PROFILE:=performance}"
: "${TUNED_DEFAULT_PROFILE:=balanced}"
: "${MANGOHUD_ENABLED:=true}"
: "${MANGOHUD_CONFIG:=fps,position=top-left,font_size=24}"

echo "╔══════════════════════════════════════════════╗"
echo "║            Запуск Steamscope                 ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "Настройки:"
echo "  • Разрешение: ${RENDER_WIDTH}x${RENDER_HEIGHT} → ${NATIVE_WIDTH}x${NATIVE_HEIGHT}"
echo "  • Частота: ${REFRESH_RATE}Hz"
echo "  • Режим Steam: ${STEAM_LAUNCH_MODE}"
echo ""

# ========== ЗАПУСК ОПТИМИЗАЦИЙ ==========
echo "Применение оптимизаций..."

# 1. Falcond - запускаем демон если он установлен и включен
if [[ "${FALCOND_ENABLED,,}" == "true" ]]; then
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet falcond 2>/dev/null; then
      echo "  • Falcond: уже запущен"
    else
      echo "  • Falcond: запуск демона оптимизации"
      if sudo systemctl start falcond 2>/dev/null; then
        echo "    ✓ Falcond запущен"
      else
        echo "    ✗ Не удалось запустить falcond"
      fi
    fi
  else
    echo "  • Falcond: systemctl не найден"
  fi
fi

# 2. Tuned - применяем игровой профиль
if [[ "${TUNED_ENABLED,,}" == "true" ]]; then
  if command -v tuned-adm >/dev/null 2>&1; then
    echo "  • Tuned: применение профиля '$TUNED_PERFORMANCE_PROFILE'"
    if sudo tuned-adm profile "$TUNED_PERFORMANCE_PROFILE" 2>/dev/null; then
      echo "    ✓ Профиль применен"
    else
      echo "    ✗ Не удалось применить профиль"
    fi
  else
    echo "  • Tuned: tuned-adm не найден"
  fi
fi

# ========== ПЕРЕМЕННЫЕ ОКРУЖЕНИЯ ==========
# Применяем переменные окружения из конфига
export LD_PRELOAD=""
export SDL_VIDEO_MINIMIZE_ON_FOCUS_LOSS=0
export __GL_SYNC_TO_VBLANK=0
export ANV_GPL=1
export mesa_glthread=true
export WLR_DRM_NO_ATOMIC=1
export WLR_RENDERER_ALLOW_SOFTWARE=1

# ========== НАСТРОЙКА GAMESCOPE ==========
# Определяем режим запуска Steam
STEAM_ARGS=""
case "${STEAM_LAUNCH_MODE,,}" in
  gamepadui) STEAM_ARGS="-gamepadui" ;;
  bigpicture|"") STEAM_ARGS="-tenfoot" ;;
  *) STEAM_ARGS="-tenfoot" ;;
esac

# Добавляем параметры реального времени если включены
GAMESCOPE_PERF_ARGS=""
if [[ "${GAMESCOPE_REALTIME,,}" == "true" ]]; then
  GAMESCOPE_PERF_ARGS="--rt --immediate-flips"
fi

# Настройка MangoHud
MANGOHUD_ARGS=""
if [[ "${MANGOHUD_ENABLED,,}" == "true" ]]; then
  export MANGOHUD=1
  [ -n "$MANGOHUD_CONFIG" ] && export MANGOHUD_CONFIG="$MANGOHUD_CONFIG"
  MANGOHUD_ARGS="--mangoapp"
fi

# Собираем команду Gamescope
GAMESCOPE_CMD="/usr/bin/gamescope \
  $GAMESCOPE_PERF_ARGS \
  $MANGOHUD_ARGS \
  $GAMESCOPE_ARGS \
  -W $NATIVE_WIDTH \
  -H $NATIVE_HEIGHT \
  -w $RENDER_WIDTH \
  -h $RENDER_HEIGHT \
  -r $REFRESH_RATE \
  -- /usr/bin/steam $STEAM_ARGS"

echo ""
echo "Запуск Steam через Gamescope..."
echo ""

# Запускаем в отдельной сессии
setsid bash -c "$GAMESCOPE_CMD" &

# Сохраняем PID для последующего завершения
GAMESCOPE_PID=$!
echo $GAMESCOPE_PID > "$SESSION_FILE"

echo "✓ Steamscope запущен (PID: $GAMESCOPE_PID)"
echo "  Разрешение: ${RENDER_WIDTH}x${RENDER_HEIGHT} → ${NATIVE_WIDTH}x${NATIVE_HEIGHT}"
echo "  Частота: ${REFRESH_RATE}Hz"
echo ""
echo "Для выхода используйте: leave-steamscope"
echo ""

ENTER_EOF

  chmod +x "$ENTER_BIN" || die "Не удалось сделать скрипт исполняемым"
  
  # Создаем скрипт завершения (упрощенная версия)
  cat > "$LEAVE_BIN" <<'LEAVE_EOF'
#!/bin/bash
set -Euo pipefail

STATE_DIR="$HOME/.cache/steamscope"
SESSION_FILE="$STATE_DIR/session.pid"

echo "╔══════════════════════════════════════════════╗"
echo "║           Завершение Steamscope              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ========== ЗАВЕРШЕНИЕ GAMESCOPE ==========
echo "Завершение Steamscope..."

if [ -f "$SESSION_FILE" ]; then
  SAVED_PID=$(cat "$SESSION_FILE" 2>/dev/null)
  if [ -n "$SAVED_PID" ] && kill -0 "$SAVED_PID" 2>/dev/null; then
    echo "  • Gamescope (PID: $SAVED_PID)..."
    kill -TERM "$SAVED_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$SAVED_PID" 2>/dev/null || true
    rm -f "$SESSION_FILE"
    echo "  ✓ Gamescope завершен"
  else
    echo "  ✗ Активная сессия не найдена"
    rm -f "$SESSION_FILE"
  fi
else
  echo "  • Завершение всех процессов Steam..."
  pkill -f "gamescope.*steam" 2>/dev/null || true
  pkill -f "steam.*tenfoot" 2>/dev/null || true
  pkill -f "steam.*gamepadui" 2>/dev/null || true
  echo "  ✓ Все процессы Steam завершены"
fi

# Завершаем фоновые процессы Steam
pkill -f "steamwebhelper" 2>/dev/null || true

# ========== ВОССТАНОВЛЕНИЕ НАСТРОЕК ==========
echo ""
echo "Восстановление настроек системы..."

# Загружаем конфиг если есть
CONFIG_FILE="$HOME/.config/steamscope/steamscope.conf"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

: "${TUNED_ENABLED:=false}"
: "${TUNED_DEFAULT_PROFILE:=balanced}"

# Tuned - восстанавливаем профиль по умолчанию
if [[ "${TUNED_ENABLED,,}" == "true" ]]; then
  if command -v tuned-adm >/dev/null 2>&1; then
    echo "  • Tuned: восстановление профиля '$TUNED_DEFAULT_PROFILE'"
    sudo tuned-adm profile "$TUNED_DEFAULT_PROFILE" 2>/dev/null || true
    echo "    ✓ Настройки восстановлены"
  fi
fi

# Falcond остается запущенным - он сам управляет оптимизациями
# Если хотите остановить falcond, раскомментируйте:
# sudo systemctl stop falcond 2>/dev/null || true

echo ""
echo "✓ Steamscope полностью завершен"
echo "  Система восстановлена в обычный режим"
echo ""

LEAVE_EOF

  chmod +x "$LEAVE_BIN" || die "Не удалось сделать скрипт исполняемым"
  
  # Создаем директорию для состояния
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  
  info "Скрипты созданы:"
  info "  Запуск: $ENTER_BIN"
  info "  Выход:  $LEAVE_BIN"
}

# ========== ИНФОРМАЦИЯ ДЛЯ ПОЛЬЗОВАТЕЛЯ ==========
show_user_info() {
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  УСТАНОВКА STEAMSCOPE ЗАВЕРШЕНА"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "  Конфигурация:"
  echo "    • Файл конфигурации: $CONFIG_FILE"
  echo "    • Скрипт запуска:    $ENTER_BIN"
  echo "    • Скрипт выхода:     $LEAVE_BIN"
  echo ""
  echo "  Для использования добавьте в конфигурацию labwc/sway:"
  echo ""
  
  echo "    # Для labwc (файл ~/.config/labwc/rc.xml):"
  echo "    <keybind key=\"S-s\">"
  echo "      <action name=\"Execute\">"
  echo "        <command>foot --title='Steamscope' -e enter-steamscope</command>"
  echo "      </action>"
  echo "    </keybind>"
  echo "    <keybind key=\"S-r\">"
  echo "      <action name=\"Execute\">"
  echo "        <command>foot --title='Steamscope' -e leave-steamscope</command>"
  echo "      </action>"
  echo "    </keybind>"
  echo ""
  echo "    # Для sway (файл ~/.config/sway/config):"
  echo "    bindsym \$mod+Shift+s exec foot --title='Steamscope' -e enter-steamscope"
  echo "    bindsym \$mod+Shift+r exec foot --title='Steamscope' -e leave-steamscope"
  echo ""
  echo "  Или используйте из терминала:"
  echo "    $ enter-steamscope"
  echo "    $ leave-steamscope"
  echo ""
  
  if [ "$NEEDS_RELOGIN" -eq 1 ]; then
    echo "  ⚠️  ВАЖНО: Необходимо выйти из системы и войти заново"
    echo "      для применения изменений групп пользователя."
    echo ""
  fi
  
  # Проверяем наличие falcond
  if check_package "falcond" || pacman -Q falcond &>/dev/null 2>&1; then
    echo "  ℹ️  Falcond обнаружен:"
    echo "      Конфигурация: /etc/falcond/config.conf"
    echo "      Профили игр: /usr/share/falcond/profiles/"
    echo ""
  else
    echo "  ℹ️  Для установки Falcond:"
    echo "      Следуйте инструкциям на:"
    echo "      https://github.com/PikaOS-Linux/falcond"
    echo ""
  fi
  
  echo "════════════════════════════════════════════════════════════════"
  echo ""
}

# ========== ОСНОВНАЯ ЛОГИКА УСТАНОВКИ ==========
main() {
  echo ""
  echo "╔═══════════════════════════════════════════════════╗"
  echo "║           Установка Steamscope                    ║"
  echo "║    Steam + Gamescope для labwc/sway              ║"
  echo "╚═══════════════════════════════════════════════════╝"
  echo ""
  
  # Флаги состояния
  NEEDS_RELOGIN=0
  
  # Проверяем окружение
  validate_environment
  
  # Проверяем зависимости Steam
  check_steam_dependencies
  
  # Проверяем конфигурацию Steam
  check_steam_config
  
  # Настраиваем права для Gamescope
  setup_gamescope_capabilities
  
  # Создаем конфигурационный файл
  create_config_file
  
  # Создаем скрипты запуска
  create_launch_scripts
  
  # Показываем информацию пользователю
  show_user_info
}

# Запускаем основную функцию
main
