-- The web app page that shows one request, for the links the inbox opens (notifications, events).
-- Every request type has a page of its own in the web app (frontend src/routes/_app/requests/...);
-- `?request=<id>` opens the record there. @side picks the tab and the list behind it:
--   approvals      the approver's view (Approvals tab: Approve/Reject, or a read-only view once decided)
--   consents       the same, on the Consents list (a consent step: Agree / Disagree)
--   cancellations  the same, on the Cancellations list (a cancellation step)
--   requests       the requester's view (Requests tab, their own list)
--   all            Requests tab with everyone's list (people who act on an approved request: a requisition)
-- NULL for a type with no web page (task_extension is decided in Project Management): no link then.
-- Keep in line with the frontend's src/features/inbox/notification-links.test.ts.
CREATE OR ALTER FUNCTION [req].[fn_request_link] (@type_code NVARCHAR(30), @request_id BIGINT, @side NVARCHAR(20))
RETURNS NVARCHAR(500)
AS
BEGIN
    DECLARE @id NVARCHAR(30) = CONVERT(NVARCHAR(30), @request_id);
    -- Overtime is decided on Attendance -> Overtime (its Applications tab, boxes as Approvals' lists).
    IF @type_code = N'overtime'
        RETURN N'/attendance/overtime?tab=' + CASE @side WHEN N'approvals' THEN N'applications'
                                                         WHEN N'consents' THEN N'applications&box=consents'
                                                         WHEN N'cancellations' THEN N'applications&box=cancellations'
                                                         ELSE N'my' END
               + N'&request=' + @id;

    DECLARE @page NVARCHAR(100) = CASE @type_code
        WHEN N'punch'          THEN N'/requests/punch'
        WHEN N'shift_swap'     THEN N'/requests/shift'
        WHEN N'transfer'       THEN N'/requests/transfer'
        WHEN N'leave'          THEN N'/requests/leave'
        WHEN N'loan'           THEN N'/requests/loan-advances'
        WHEN N'work_from_home' THEN N'/requests/work-from-home'
        WHEN N'official_visit' THEN N'/requests/official-visits'
        WHEN N'promotion'      THEN N'/requests/promotion'
        WHEN N'relaxation'     THEN N'/requests/relaxation'
        WHEN N'rest_day'       THEN N'/requests/rest-days'
        WHEN N'travel'         THEN N'/requests/travel'
        WHEN N'resignation'    THEN N'/requests/resignation'
        WHEN N'expense'        THEN N'/requests/expense'
        WHEN N'air_ticket'     THEN N'/requests/air-tickets'
        WHEN N'requisition'    THEN N'/requests/requisition'
    END;
    IF @page IS NULL
        RETURN NULL;
    RETURN @page + CASE @side WHEN N'approvals' THEN N'?tab=approvals&request='
                              WHEN N'consents' THEN N'?tab=approvals&view=consents&request='
                              WHEN N'cancellations' THEN N'?tab=approvals&view=cancellations&request='
                              WHEN N'all' THEN N'?scope=all&request='
                              ELSE N'?request=' END + @id;
END
