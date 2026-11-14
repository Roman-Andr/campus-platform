"""Initial skill tags; administrators extend and edit the reference later."""

from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from campus.core import clock
from campus.modules.identity.models import SkillTag

# (code, Russian name, English name)
SKILL_TAGS: tuple[tuple[str, str, str], ...] = (
    ("english", "Английский язык", "English"),
    ("german", "Немецкий язык", "German"),
    ("french", "Французский язык", "French"),
    ("chinese", "Китайский язык", "Chinese"),
    ("spanish", "Испанский язык", "Spanish"),
    ("russian", "Русский язык", "Russian"),
    ("mathematics", "Математика", "Mathematics"),
    ("statistics", "Статистика", "Statistics"),
    ("physics", "Физика", "Physics"),
    ("economics", "Экономика", "Economics"),
    ("python", "Python", "Python"),
    ("java", "Java", "Java"),
    ("javascript", "JavaScript", "JavaScript"),
    ("sql", "SQL", "SQL"),
    ("data-analysis", "Анализ данных", "Data analysis"),
    ("machine-learning", "Машинное обучение", "Machine learning"),
    ("excel", "Excel", "Excel"),
    ("graphic-design", "Графический дизайн", "Graphic design"),
    ("photography", "Фотография", "Photography"),
    ("video-editing", "Видеомонтаж", "Video editing"),
    ("guitar", "Гитара", "Guitar"),
    ("piano", "Фортепиано", "Piano"),
    ("singing", "Вокал", "Singing"),
    ("drawing", "Рисование", "Drawing"),
    ("dancing", "Танцы", "Dancing"),
    ("chess", "Шахматы", "Chess"),
    ("cooking", "Кулинария", "Cooking"),
    ("running", "Бег", "Running"),
    ("swimming", "Плавание", "Swimming"),
    ("yoga", "Йога", "Yoga"),
    ("public-speaking", "Публичные выступления", "Public speaking"),
    ("academic-writing", "Академическое письмо", "Academic writing"),
    ("bike-repair", "Ремонт велосипеда", "Bike repair"),
    ("sewing", "Шитьё", "Sewing"),
)


async def seed_skill_tags(session: AsyncSession) -> int:
    """Add missing tags by code; existing ones, maybe edited, stay as they are.

    Returns the number of tags added."""
    now = clock.now()
    result = await session.execute(
        insert(SkillTag)
        .values(
            [
                {
                    "code": code,
                    "name_ru": ru,
                    "name_en": en,
                    "created_at": now,
                    "updated_at": now,
                }
                for code, ru, en in SKILL_TAGS
            ]
        )
        .on_conflict_do_nothing(index_elements=["code"])
        .returning(SkillTag.id)
    )
    return len(result.all())
