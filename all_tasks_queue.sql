SET session TIME ZONE 'UTC';
with
all_assessd_tasks as (  ------      таблица фильтр уже проверенных заданий
    select distinct
        question_uuid
    from cms_question_assessor_status
    where assessor_status is not null
    UNION ALL
    select distinct
        cjd.document_question_uuid
    from cms_job_duplicate as cjd
    join cms_question_assessor_status as cqas on cjd.query_question_uuid = cqas.question_uuid
    left join cms_job_duplicate as cjd2
                on cjd.query_question_uuid = cjd2.query_question_uuid
                    and cjd.document_question_uuid = cjd2.document_question_uuid
                    and coalesce(cjd2.order, 1) > 1
                    and cjd2.relevance = 0
    where
        cjd.relevance = 1
        and coalesce(cjd.order, 1) = 1
        and cjd2.query_question_uuid is null
        and cqas.assessor_status is not null
    UNION ALL
    select distinct
        cjd.query_question_uuid
    from cms_job_duplicate as cjd
    join cms_question_assessor_status as cqas on cjd.document_question_uuid = cqas.question_uuid
    left join cms_job_duplicate as cjd2
                on cjd.query_question_uuid = cjd2.query_question_uuid
                    and cjd.document_question_uuid = cjd2.document_question_uuid
                    and coalesce(cjd2.order, 1) > 1
                    and cjd2.relevance = 0
    where 
        cjd.relevance = 1
        and coalesce(cjd.order, 1) = 1
        and cjd2.query_question_uuid is null
        and cqas.assessor_status is not null 
),
all_assessd_tasks_f as (
    select distinct question_uuid
    from all_assessd_tasks
),
assessed_tasks_wo_similar as (
    select distinct question_uuid
    from cms_question_assessor_status
    where assessor_status is not null
),

/*    tinder_import as (    ---->>> исключения импорт бота
    select
        distinct cf.cms_question_uuid
    from cms_feedback as cf
    join cms_question as cq on cf.cms_question_uuid = cq.uuid
    join cms_question as cq2 on cq.answer_id = cq2.answer_id
    where
        cf.attempt_uuid != '00000000-0000-0000-0000-000000000000'
        and cf.cms_question_uuid is not null 
        and cf.score = 0
        and date_trunc('day', cf.created_at + interval '3 hours') >= '2022-01-20'
        and coalesce(cf.comment_group, '') != 'Too late'
        and coalesce(cq2.import_type, '') = 'with-answer'
),      */
all_negative_feedback as (
    select
        cf.cms_question_uuid as uuid,
        max(cf.created_at) as created_at
    from cms_feedback as cf
    join cms_question as cq on cf.attempt_uuid = cq.attempt_uuid
    --left join tinder_import as ti on cf.cms_question_uuid = ti.cms_question_uuid
    where 
        cf.attempt_uuid != '00000000-0000-0000-0000-000000000000'
        and cf.cms_question_uuid is not null 
        and cf.score = 0
        and date_trunc('day', cf.created_at + interval '3 hours') >= '2022-01-20'
        and coalesce(cf.comment_group, '') != 'Too late'
        --and coalesce(cq.import_type, '') != 'with-answer'
        --and ti.cms_question_uuid is null 
    group by 1 
),
before_zero_priority as ( ------  задачи с негативным фидбеком перед нулевым приоритетом
    select 
        'negative feedback' as assignee,
        anf.uuid,
        row_number() over(order by anf.created_at) as num,
        date '1999-12-31' as priority,
        0 as percent_assessed
        
    from all_negative_feedback as anf
    left join all_assessd_tasks_f as aat on anf.uuid = aat.question_uuid
    where 
        aat.question_uuid is null 
),
new_methodist as ( ----    таблица для определения новых методистов (первые 3 дня работы методиста)
    select 
        period_msk,
        assignee,
        row_number() over(partition by assignee order by period_msk) as num
    from (
        select
            date_trunc('day', cqs.created_at + interval '3 hours') as period_msk,
            cqs.assignee,
            COUNT(*) as qty
        from cms_question_status cqs
        join cms_user cu on cqs.assignee = cu.name and cqs.created_at between cu.created_at and coalesce(cu.deleted_at, '2031-12-31')
            where
                cu.role = 'methodist'
                and cqs.assignee_role = 'methodist'
        group by 1,2
    ) as a
),
new_methodist_tasks_0 as (      ------кол-во решенных задач в первые три дня новичками
    select distinct 
        cqs.question_uuid,
        cqs.assignee,
        cq.attempt_uuid,
        cq.popularity,
        date_trunc('day', cqs.created_at + interval '3 hours') as period_msk
    from cms_question_status as cqs
    join cms_question as cq on cqs.question_uuid = cq.uuid 
    join new_methodist as nm on cqs.assignee = nm.assignee and nm.num <= 3 and date_trunc('day', cqs.created_at + interval '3 hours') = nm.period_msk
    where
        cqs.status = 'answered'
        and cqs.assignee_role = 'methodist'
        and lower(coalesce(cqs.status_reason, '')) != 'identical'
        and date_trunc('day', cqs.created_at + interval '3 hours') >= '2021-12-24' --------     Дата старта кнопки!!! Можно менять
),
new_methodist_stats as (        --------  считаем сколько уже проверили и сколько надо
    select
        assignee,
        period_msk,
        COUNT(distinct n.question_uuid) as total_solved,
        ceiling(COUNT(distinct n.question_uuid)*0.8) as need_check,
        COUNT(distinct case when at.question_uuid is not null then n.question_uuid end) as assessed,
        coalesce(COUNT(distinct case when at.question_uuid is not null then n.question_uuid end), 0)::float/COUNT(distinct n.question_uuid)*100.00 as percent_assessed
    from new_methodist_tasks_0 as n
    left join assessed_tasks_wo_similar as at on n.question_uuid = at.question_uuid
    group by 1,2
),
new_methodist_tasks_1 as (      ------  смотрим все задачи и сортируем их по негативному фидбеку
    select
        assignee,
        n.period_msk,
        n.question_uuid,
        row_number() over(partition by assignee, n.period_msk order by n.popularity desc) as num
    from new_methodist_tasks_0 as n
    left join all_assessd_tasks_f as at on n.question_uuid = at.question_uuid
    where
        at.question_uuid is null
),
zero_priority as ( ------  задачи нулевого приоритета
    select 
        n.assignee,
        question_uuid,
        num,
        date '1998-12-31' as priority,
        percent_assessed
        
    from new_methodist_tasks_1 as n 
    join new_methodist_stats as c on n.assignee = c.assignee and n.period_msk = c.period_msk
    where 
        c.need_check - c.assessed > 0
        and n.num <= c.need_check - c.assessed
    order by c.period_msk, c.percent_assessed, num
),
other_tasks_0 as (        ----- задачи по всем остальным методистам
    select distinct 
        cqs.question_uuid,
        cqs.assignee,
        cqs.assignee_role,
        cq.attempt_uuid,
        cq.popularity,
        date_trunc('day', cqs.created_at + interval '3 hours') as period_msk,
        cq.correctness_score,
        cq.design_score,
        case when cq.correctness_score is not null then 1 else 0 end as flg_checked

    from cms_question_status as cqs
    join cms_question as cq on cqs.question_uuid = cq.uuid
    left join new_methodist as nm on cqs.assignee = nm.assignee and nm.num <= 3 and date_trunc('day', cqs.created_at + interval '3 hours') = nm.period_msk
    where
        cqs.status = 'answered'
        and cqs.assignee_role in ('operator', 'methodist')
        and lower(coalesce(cqs.status_reason, '')) != 'identical'
        and date_trunc('day', cqs.created_at + interval '3 hours') >= '2021-12-24' --------     Дата старта кнопки!!! Можно менять
        and nm.assignee is null ------ убираем новичков
),
retro_mistake as (
    select  
        a.period_msk,
        a.assignee,
        a.assignee_role,
        COUNT(distinct b.question_uuid) as qty_solved,
        100 - (0.7*AVG(case when b.flg_checked = 1 then b.correctness_score end) + 0.3*AVG(case when b.flg_checked = 1 then b.design_score end)) as mistake 
    from other_tasks_0 as a 
    left join other_tasks_0 as b on a.assignee = b.assignee and b.period_msk between a.period_msk - interval '15 days' and a.period_msk - interval '1 day'
    where 
        1=1
    group by 1,2,3
),
next_percent as (
    select 
        period_msk,
        assignee,
        assignee_role,
        qty_solved,
        mistake,
        case when assignee_role = 'methodist' and mistake <= 6 then 0.06
            when assignee_role = 'methodist' and mistake <= 11 then 0.11
            when assignee_role = 'methodist' and mistake <= 16 then 0.16
            when assignee_role = 'methodist' and mistake > 16 then 0.20
            when assignee_role = 'operator' and mistake < 10 then 0.10
            when assignee_role = 'operator' and mistake >= 10 then mistake::float/100.00
        end as future_percent
    from retro_mistake
),
next_percent_f as (
    select 
        period_msk,
        assignee,
        np.future_percent,
        assignee_role,
        qty_solved,
        mistake,
        ((1.28*1.28*np.future_percent*(1-np.future_percent))/(0.04*0.04))/(1+(1.28*1.28*np.future_percent*(1-np.future_percent)/(0.04*0.04)-1)/np.qty_solved)::float/np.qty_solved as percent
    
    from next_percent as np
),
other_stats_0 as (        --------  считаем сколько уже проверили и сколько надо
    select
        assignee,
        period_msk,
        COUNT(distinct n.question_uuid) as total_solved,
        --ceiling(COUNT(distinct n.question_uuid)*0.4) as need_check,
        COUNT(distinct case when at.question_uuid is not null then n.question_uuid end) as assessed,
        coalesce(COUNT(distinct case when at.question_uuid is not null then n.question_uuid end), 0)::float/COUNT(distinct n.question_uuid)*100.00 as percent_assessed
    from other_tasks_0 as n
    left join assessed_tasks_wo_similar as at on n.question_uuid = at.question_uuid
    group by 1,2
),
other_stats as (
    select 
        os.*,
        --np.mistake,
        --np.percent,
        --greatest(0.1, np.percent),
        ceiling(total_solved*greatest(0.1, np.percent)) as need_check
    from other_stats_0 as os 
    join next_percent_f as np on os.assignee = np.assignee and os.period_msk = np.period_msk
),
other_tasks_1 as (      ------  смотрим все задачи и сортируем их по негативному фидбеку
    select
        assignee,
        n.question_uuid,
        n.period_msk,
        row_number() over(partition by assignee, n.period_msk order by n.popularity desc) as num
    from other_tasks_0 as n
    left join all_assessd_tasks_f as at on n.question_uuid = at.question_uuid
    where
        at.question_uuid is null
),
first_priority as ( ------  задачи первого приоритета
    select 
        n.assignee,
        question_uuid,
        num,
        c.period_msk as priority,
        percent_assessed
        
    from other_tasks_1 as n
    join other_stats as c on n.assignee = c.assignee and n.period_msk = c.period_msk
    where
        c.need_check - c.assessed > 0
        and n.num <= c.need_check - c.assessed
    order by c.period_msk, c.percent_assessed, num
),
failed_tasks_0 as (        ----- failed задачи по методистам 
    select distinct 
        cqs.question_uuid,
        cqs.assignee,
        cq.attempt_uuid,
        cq.popularity,
        date_trunc('day', cqs.created_at + interval '3 hours') as period_msk
    from cms_question_status as cqs
    join cms_question as cq on cqs.question_uuid = cq.uuid
    where
        cqs.status = 'failed'
        and cqs.assignee_role = 'methodist'
        and date_trunc('day', cqs.created_at + interval '3 hours') >= '2021-12-24' --------     Дата старта кнопки!!! Можно менять
),
failed_stats as (        --------  считаем сколько уже проверили и сколько надо
    select
        assignee,
        period_msk,
        COUNT(distinct n.question_uuid) as need_check,
        COUNT(distinct case when at.question_uuid is not null then n.question_uuid end) as assessed,
        coalesce(COUNT(distinct case when at.question_uuid is not null then n.question_uuid end), 0)::float/COUNT(distinct n.question_uuid)*100.00 as percent_assessed
    from failed_tasks_0 as n
    left join assessed_tasks_wo_similar as at on n.question_uuid = at.question_uuid
    group by 1,2
),
failed_tasks_1 as (      ------  смотрим все failed задачи и сортируем их по негативному фидбеку
    select
        assignee,
        n.question_uuid,
        n.period_msk,
        row_number() over(partition by assignee, n.period_msk order by n.popularity desc) as num
    from failed_tasks_0 as n
    left join all_assessd_tasks_f as at on n.question_uuid = at.question_uuid
    where
        at.question_uuid is null
),
second_priority as ( ------  задачи второго приоритета
    select 
        n.assignee,
        question_uuid,
        num,
        c.period_msk as priority,
        percent_assessed
        
    from failed_tasks_1 as n 
    join failed_stats as c on n.assignee = c.assignee and n.period_msk = c.period_msk
    where 
        c.need_check - c.assessed > 0
        and n.num <= c.need_check - c.assessed
    order by c.period_msk, c.percent_assessed, num
),
canceled_tasks_0 as (        ----- canceled задачи по методистам 
    select distinct 
        cqs.question_uuid,
        cqs.assignee,
        cq.attempt_uuid,
        cq.popularity,
        date_trunc('day', cqs.created_at + interval '3 hours') as period_msk
    from cms_question_status as cqs
    join cms_question as cq on cqs.question_uuid = cq.uuid
    where
        cqs.status = 'canceled'
        and cqs.assignee_role = 'methodist'
        and date_trunc('day', cqs.created_at + interval '3 hours') >= '2022-03-01' --------     Дата старта кнопки!!! Можно менять
),
canceled_stats as (        --------  считаем сколько уже проверили и сколько надо
    select
        assignee,
        period_msk,
        ceiling(COUNT(distinct n.question_uuid)*1) as need_check,       --------меняю на 100 процентов вместо 75%
        COUNT(distinct case when at.question_uuid is not null then n.question_uuid end) as assessed,
        coalesce(COUNT(distinct case when at.question_uuid is not null then n.question_uuid end), 0)::float/COUNT(distinct n.question_uuid)*100.00 as percent_assessed
    from canceled_tasks_0 as n
    left join assessed_tasks_wo_similar as at on n.question_uuid = at.question_uuid
    group by 1,2
),
canceled_tasks_1 as (      ------  смотрим все canceled задачи и сортируем их по негативному фидбеку
    select
        assignee,
        n.question_uuid,
        n.period_msk,
        row_number() over(partition by assignee, n.period_msk order by n.popularity desc) as num
    from canceled_tasks_0 as n
    left join all_assessd_tasks_f as at on n.question_uuid = at.question_uuid
    where
        at.question_uuid is null
),
third_priority as ( ------  задачи второго приоритета
    select 
        n.assignee,
        question_uuid,
        num,
        c.period_msk as priority,
        percent_assessed
        
    from canceled_tasks_1 as n 
    join canceled_stats as c on n.assignee = c.assignee and n.period_msk = c.period_msk
    where 
        c.need_check - c.assessed > 0
        and n.num <= c.need_check - c.assessed
    order by c.period_msk, c.percent_assessed, num
),
popular_questions as (
    select 
        'popular question' as assignee,
        cq.uuid as question_uuid,
        row_number() over(order by created_at desc) as num,
        '2032-12-31'::date as priority,
        0 as percent_assessed
        
    from cms_question as cq 
    left join all_assessd_tasks_f as at on cq.uuid = at.question_uuid
    where 
        cq.popularity > 0
        and cq.correctness_score is null
        and cq.design_score is null
        and at.question_uuid is null 
)
select *    --------    задачи с негативным фидбеком (идут самым первым приоритетом - даже до новичков)
from before_zero_priority
UNION ALL
select *        ------  answered вопросы по новичкам
from zero_priority
UNION all 
select *        ------  answered по всем оставшимся М и О 
from first_priority
where priority >= '2022-03-07'                    --поменял дату с 2022-01-18 на 2022-03-07 для отсечки старых ансведов, Шкляев 12.03
UNION all 
select *            ------ failed по М 
from second_priority
UNION all 
select *            ------ canceled по М 
from third_priority
UNION ALL
select *             ------ остальные популярные вопросы
from popular_questions
order by priority, percent_assessed, num

