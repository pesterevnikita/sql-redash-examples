select cq.created_at,
cq.uuid,
assignee, 
status, 
body_searchable,
cf.user_input,
cf.score_description,
assessor_status,
correctness_score


from cms_question as cq
left join cms_feedback as cf --данные о фидбеке хранятся в отдельной таблице
    on cf.cms_question_uuid=cq.uuid 

where cq.user_id_external= '{{ user }}' --ввод айди юзера со страницы в цмс
order by created_at desc