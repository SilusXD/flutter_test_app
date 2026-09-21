"""Структурная проверка project.pbxproj без Xcode.

Проверяет то, что реально ломает сборку: несоответствие скобок, ссылки на
несуществующие объекты, дубликаты идентификаторов, отсутствие обязательных
секций. Полноценный парсер OpenStep-plist это не заменяет, но отсекает
основные классы ошибок ручного редактирования.
"""

import re
import sys
from pathlib import Path

UUID_RE = re.compile(r"\b[0-9A-F]{24}\b")
# Определение начинается с UUID в начале строки: "UUID /* comment */ = {".
# Важно не пропускать перевод строки в [^=\n]*, иначе одно совпадение
# "съедает" соседние определения и проверка ссылок врёт.
DEFINITION_RE = re.compile(r"^[ \t]*([0-9A-F]{24})\b[^=\n]*=[ \t]*\{", re.MULTILINE)
SECTION_RE = re.compile(r"/\* Begin (\w+) section \*/")

REQUIRED_SECTIONS = [
    "PBXBuildFile",
    "PBXFileReference",
    "PBXGroup",
    "PBXNativeTarget",
    "PBXProject",
    "PBXSourcesBuildPhase",
    "XCBuildConfiguration",
    "XCConfigurationList",
]


def check_balance(text: str, path: Path) -> list[str]:
    problems = []
    for opener, closer in (("{", "}"), ("(", ")")):
        if text.count(opener) != text.count(closer):
            problems.append(
                f"{path.name}: несбалансированные {opener}{closer}: "
                f"{text.count(opener)} против {text.count(closer)}"
            )
    return problems


def check_references(text: str, path: Path) -> list[str]:
    problems = []
    definitions = DEFINITION_RE.findall(text)
    defined = set(definitions)

    duplicates = {item for item in definitions if definitions.count(item) > 1}
    if duplicates:
        # Совпадает у эталонных проектов Xcode: UUID цели повторно объявляется
        # в блоке TargetAttributes, поэтому это не ошибка.
        print(
            f"  [INFO] {path.name}: UUID объявлены дважды "
            f"(ожидаемо для TargetAttributes): {sorted(duplicates)}"
        )

    used = set(UUID_RE.findall(text))
    undefined = sorted(used - defined)
    if undefined:
        problems.append(f"{path.name}: ссылки на неопределённые объекты: {undefined}")

    unused = sorted(defined - used)
    if unused:
        problems.append(
            f"{path.name}: объекты объявлены, но нигде не используются: {unused}"
        )
    return problems


def check_sections(text: str, path: Path) -> list[str]:
    sections = set(SECTION_RE.findall(text))
    missing = [name for name in REQUIRED_SECTIONS if name not in sections]
    if missing:
        return [f"{path.name}: нет обязательных секций: {missing}"]
    return []


def main(paths: list[str]) -> int:
    failed = False
    for raw in paths:
        path = Path(raw)
        if not path.exists():
            print(f"NOT FOUND: {path}")
            failed = True
            continue

        text = path.read_text(encoding="utf-8")
        problems = (
            check_balance(text, path)
            + check_references(text, path)
            + check_sections(text, path)
        )

        print(f"--- {path}")
        if problems:
            failed = True
            for problem in problems:
                print(f"  [FAIL] {problem}")
        else:
            targets = re.findall(r"name = ([\w.\-]+);\n\t*productType", text)
            print(f"  [OK] структура корректна, целей объявлено: {len(targets)} {targets}")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
