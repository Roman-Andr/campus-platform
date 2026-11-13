"""Utility to combine Typst files."""

import glob
import os
import re


def combine_typ_files() -> None:
    """Combine .typ files from sections folder into single output."""
    # Папка с файлами
    folder = "sections"

    # Получаем список всех .typ файлов в папке
    typ_files = glob.glob(os.path.join(folder, "*.typ"))

    # Функция для извлечения номера из имени файла
    def extract_number(filename):
        # Ищем паттерн "число-что-то.typ"
        match = re.search(r"(\d+)-", os.path.basename(filename))
        if match:
            return int(match.group(1))
        return float("inf")  # Если номер не найден, помещаем в конец

    # Сортируем файлы по номеру
    sorted_files = sorted(typ_files, key=extract_number)

    # Собираем содержимое всех файлов
    combined_content = []

    for file_path in sorted_files:
        try:
            with open(file_path, encoding="utf-8") as file:
                content = file.read().strip()
                combined_content.append(content)
                print(f"Обработан файл: {os.path.basename(file_path)}")
        except Exception as e:
            print(f"Ошибка при чтении файла {file_path}: {e}")

    # Объединяем содержимое с двумя пустыми строками между файлами
    result = "\n\n\n".join(combined_content)

    # Записываем результат в файл
    output_file = "/mnt/d/downloads/combined_output.txt"
    try:
        with open(output_file, "w", encoding="utf-8") as f:
            f.write(result)
        print(f"\nФайлы успешно объединены в {output_file}")
        print(f"Обработано файлов: {len(sorted_files)}")
    except Exception as e:
        print(f"Ошибка при записи файла {output_file}: {e}")


if __name__ == "__main__":
    combine_typ_files()
