"""Demonstration texts only; the operator supplies pilot documents."""

from sqlalchemy.ext.asyncio import AsyncSession

from campus.modules.identity.consents import (
    DocumentKind,
    current_documents,
    publication_lock,
    publish_document,
)

TEXTS = {
    DocumentKind.RULES: (
        "Правила сообщества «Кампус». Запрещены: товары и услуги, оборот которых "
        "ограничен законом; алкоголь, табак, лекарства (в том числе в фудшеринге); "
        "выполнение учебных работ за другого, в том числе за баллы; реклама и "
        "коммерческая перепродажа; оскорбления, угрозы и раскрытие чужих "
        "персональных данных; второй аккаунт, выдача себя за другого и указание "
        "чужого общежития или факультета.",
        "Campus community rules. Prohibited: legally restricted goods and "
        "services; alcohol, tobacco and medicines (including food sharing); "
        "doing another person's academic work, including for points; advertising "
        "and commercial resale; insults, threats and disclosure of others' "
        "personal data; second accounts, impersonation and claiming another "
        "dormitory or faculty.",
    ),
    DocumentKind.POLICY: (
        "Демонстрационная политика обработки ПДн. Используйте только тестовые "
        "данные. Кампус хранит корпоративную почту, имя, профиль, публикации и "
        "журнал согласий для работы студенческого сообщества. Данные доступны "
        "сервису и уполномоченным администраторам. Выгрузка и удаление данных "
        "выполняются по запросу пользователя. Передача за рубеж требует "
        "отдельного согласия. До пилота оператор публикует рабочую политику.",
        "Demonstration privacy policy. Use test data only. Campus stores "
        "university email, names, profiles, posts and consent history to operate "
        "the student community. The service and authorized administrators "
        "access these data. Users may request export and account deletion. "
        "Cross-border transfer needs separate consent. The operator must "
        "publish an operational policy before a pilot.",
    ),
    DocumentKind.PROCESSING: (
        "Демонстрационное согласие: разрешаю обработку тестовых почты, имени, "
        "профиля, публикаций и решений пользователя для работы Кампуса до "
        "удаления аккаунта. Отзыв выполняется удалением аккаунта. Для реальных "
        "данных оператор должен опубликовать рабочий документ.",
        "Demonstration consent: I allow processing of my test email, name, "
        "profile, posts and consent decisions to operate Campus until account "
        "deletion. Withdraw by deleting the account. The operator must publish "
        "an operational document before processing real data.",
    ),
    DocumentKind.CROSS_BORDER: (
        "Отдельное необязательное демонстрационное согласие: разрешаю "
        "трансграничную передачу текста уведомлений через FCM и Telegram и "
        "запросов к ИИ-провайдеру. Согласие можно отозвать в любой момент; "
        "основные функции Кампуса останутся доступны. Только для тестовых "
        "данных; до пилота оператор уточняет получателей и страны передачи.",
        "Separate optional demonstration consent: I allow cross-border "
        "transfer of notification text through FCM and Telegram and requests "
        "to the AI provider. I may withdraw at any time while retaining core "
        "Campus features. Test data only; before a pilot the operator must "
        "specify recipients and destination countries.",
    ),
}


async def seed_documents(session: AsyncSession) -> None:
    """Add only missing kinds; never republish or replace an existing text."""
    await publication_lock(session, exclusive=True)
    existing = {d.kind for d in await current_documents(session)}
    for kind, (ru, en) in TEXTS.items():
        if kind not in existing:
            await publish_document(session, kind, text_ru=ru, text_en=en)
