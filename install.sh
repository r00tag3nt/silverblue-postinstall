#!/bin/bash
set -e

# Перевірка root-прав
if [[ $EUID -ne 0 ]]; then
   echo "Цей скрипт потрібно запускати від імені root (sudo)."
   exit 1
fi

# Оновлення системи
rpm-ostree upgrade

# Додавання RPM Fusion
rpm-ostree install --apply-live \
    https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm

# Встановлення необхідних пакетів
rpm-ostree install podman virt-manager

# Виявлення NVIDIA GPU та встановлення драйверів
if lspci | grep -i nvidia; then
    echo "NVIDIA GPU знайдено, встановлюємо драйвери..."
    rpm-ostree install akmod-nvidia xorg-x11-drv-nvidia-cuda
else
    echo "NVIDIA GPU не знайдено, пропускаємо встановлення драйверів."
fi

# Встановлення мультимедійних кодеків
rpm-ostree install gstreamer1-libav gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld \
    gstreamer1-plugins-ugly gstreamer1-plugins-ugly-free gstreamer1-plugins-good gstreamer1-plugins-base \
    ffmpeg-libs

# Перевірка дозволів Flatpak
if command -v flatpak &> /dev/null; then
    echo "Перевіряємо дозволи Flatpak..."
    flatpak --print-permissions || echo "Помилка перевірки Flatpak permissions"

    # Перевірка наявності Flathub у списку репозиторіїв
    if flatpak remotes | grep -q flathub; then
        echo "Flathub вже додано."
    else
        echo "Flathub не знайдено, додаємо..."
        flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    fi
else
    echo "Flatpak не встановлено. Пропускаємо перевірку дозволів та Flathub."
fi

# Увімкнення автоматичних оновлень
if systemctl is-enabled rpm-ostreed-automatic.service &> /dev/null; then
    echo "Автоматичне оновлення вже увімкнено."
else
    echo "Увімкнення автоматичних оновлень..."
    systemctl enable --now rpm-ostreed-automatic.timer
fi

# Встановлення та налаштування firewalld
if ! rpm -q firewalld &> /dev/null; then
    echo "FirewallD не встановлено. Встановлюємо..."
    rpm-ostree install firewalld
    systemctl enable --now firewalld
else
    echo "FirewallD вже встановлено."
fi

# Встановлення програми керування firewall
rpm-ostree install firewall-config

# Встановлення та активація Fail2Ban
rpm-ostree install fail2ban
systemctl enable --now fail2ban

# Налаштування SSH
echo "Бажаєте встановити та увімкнути SSH? (y/n)"
read -r enable_ssh
if [[ "$enable_ssh" == "y" ]]; then
    rpm-ostree install openssh-server
    systemctl enable --now sshd
    echo "Порт 22 буде відкрито для SSH."
    firewall-cmd --permanent --add-port=22/tcp

    echo "Дозволити вхід root по SSH? (y/n)"
    read -r root_ssh
    if [[ "$root_ssh" == "y" ]]; then
        sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
        systemctl restart sshd
        echo "Вхід root по SSH дозволено."
    else
        echo "Вхід root по SSH залишено вимкненим."
    fi
else
    echo "SSH не буде встановлено."
fi

firewall-cmd --reload

# Запит користувача про відкриття портів
echo "Бажаєте залишити певні порти відкритими? (введіть номери портів через пробіл або натисніть Enter для пропуску)"
read -r open_ports
if [[ -n "$open_ports" ]]; then
    for port in $open_ports; do
        firewall-cmd --permanent --add-port=${port}/tcp
    done
    firewall-cmd --reload
    echo "Зазначені порти відкриті."
else
    echo "Жодні додаткові порти не відкривалися."
fi

# Завершення
echo "Встановлення завершено! Будь ласка, перезавантажте систему: sudo systemctl reboot"
