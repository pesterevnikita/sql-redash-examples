SET session TIME ZONE 'UTC';
with

answers as (                       
    select  cqs.created_at,
     cqs.question_uuid,
    cqs.assignee,
    lower(jsonb_array_elements(cq.messages)::jsonb#>>'{text}') as note,
     --выделяю из jsonb текстовые заметки и убираю капс чтобы потом проще искать
    cus.name,
    cq.user_id_external,
    cq.user_type_external,
    correctness_score+design_score as corr_des
    
    from cms_question_status as cqs
    join cms_question as cq 
        on cqs.question_uuid = cq.uuid
    left join cms_question_assessor_status as cas
     --соединяю разную инфу из разных таблиц, ассессмент, юзер external
        on cas.question_uuid=cq.uuid
    left join cms_user as cus
        on cus.uuid=cas.author_uuid
    where
        cqs.status = 'answered'
        and cqs.assignee_role in ('methodist')
        and lower(coalesce(cqs.status_reason, '')) != 'identical'
        and date_trunc('day', cqs.created_at + interval '3 hours') 
            between '{{date range.start}}' and '{{date range.end}}'
)

select distinct on (created_at) created_at,
 'https://solver-cms.skyeng.ru/cms/question/'||question_uuid as link,
assignee, 
note::text,
'' as count, --пустой столбец для последующей ручной проверки

case when user_type_external='manychat' then 'https://manychat.com/fb107134044913547/chat/'||user_id_external
    when user_type_external='solver-app' then 'https://solver-cms.skyeng.ru/cms/app/sessions?userIdExternal='||user_id_external
    else '-'
end as user, 
--ссылки на external юзера для последующей аналитики, использовали ли юзеры часто эту функцию намеренно

'' as how_solved, --пустой столбец тоже
name as assessor,
case when corr_des =200 then 'checked' --статус ассессинга
    when corr_des>0 then 'edited'
    else '-'
end as assessing

from answers
where note like '%many%'
--ищем вариации слова many, в одной сущности может быть решено несколько задач,
--вся выгрузка нужна для подсчёта зп этих решений


