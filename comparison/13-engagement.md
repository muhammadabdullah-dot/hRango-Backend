# 13 Engagement: newsfeed and surveys — documents vs ERD vs backend

Status: first build done (backend `/api/engagement`, schema `eng`). Announcements stay where the
Organisation module put them (`/api/organisation/announcements`, `eng.usp_announcement*`, unchanged).

Sources:

- **Figma "HRango Dashboard App Version"** frames read on 2026-10-19 and recorded in `erd/source/14-eng.md`:
  Newsfeed, Create Post ("What would you like to share?", photos and videos, chip "Public"), Reactions on Post
  (a list of who reacted), Comment written (comments with Reply and Like and timestamps), "2.5k Views",
  My Posts (Edit Post, Delete, Copy link), Announcements, Notifications. These notes are the document record.
- **Survey popup and builder**: `requirements/HRango - Shift Module UX/README.md`, section 03 (frame 113:258):
  popup "Survey Available (09)" with previous / next, title, "Your feedback is valuable...", Skip and Response
  buttons; the live builder behind it: survey title, closing date, Preview, "What would you like to ask?",
  option rows, "Add New Option", question types Multiple Choice, Short Answer, Paragraph, Dropdown,
  Check Boxes, Linear Scale; Save and Back.
- **Feature lists**: "Employee Engagement Feeds" (feature icon and website feature list,
  `requirements/HRango - UI design/All Dashboards/09-Assets-Website-and-Marketing/README.md`); "company news"
  under employee self-service in `requirements/HRango - Existing Product (web research)/README.md`.
- **Mini SRS** (`HRango - Mini SRS.pdf`, v0.2): no engagement requirement; M1–M15 do not list it. NFR-3
  (changes recorded with user and time) and ACC-7 (scopes) apply.
- Frontend: no newsfeed or survey screens (its mock data is not a specification).

## Screens and features

| Screen / feature | Documents | ERD tables | Endpoints | Decision |
|---|---|---|---|---|
| Newsfeed | App Version "Newsfeed" | post (+ media, reactions, comments, views) | `GET /posts` | Build: paged, pinned first then newest; only posts the caller's audience reaches |
| Create Post: text, several photos / videos, audience chip | "Create Post", chip "Public" | post, post_media, core.stored_file | `POST /posts` (upload first: `POST /api/files`, module `engagement`) | Build: text up to 5000, up to 10 photos / videos (setting, 1–20), audience public / department / branch, @mentions |
| Reactions on a post, "Reactions on Post" list | "Reactions on Post", "Liked" | post_reaction | `PUT /posts/{id}/reaction`, `GET /posts/{id}/reactions` | Build: six kinds (like, love, celebrate, support, insightful, funny), one per person, counts per kind and "my reaction" |
| Comments with Reply and Like | "Comment written" | post_comment, post_comment_like, post_mention | `GET/POST /posts/{id}/comments`, `PUT/DELETE /comments/{id}`, `PUT /comments/{id}/like` | Build: threads one level deep, likes, @mentions, edit and delete own |
| Views ("2.5k Views") | Newsfeed card | post_view | `POST /posts/{id}/view` | Build: once per person; the author's own views do not count |
| My Posts: Edit Post, Delete, Copy link | "My Posts" | post | `GET /my-posts`, `PUT /posts/{id}`, `DELETE /posts/{id}`; `link` on every post | Build. Copy link copies `link` (`/engagement/posts/{id}`), opened with `GET /posts/{id}` |
| Moderation (pin, hide, delete anyone's) | none (HR SaaS need) | post.is_pinned / is_hidden / is_deleted | `GET /moderation/posts`, `PATCH /posts/{id}/pin`, `PATCH /posts/{id}/hide` | Build (designed here) |
| Settings: who may post, comments on/off, media per post | none | core.company_setting (module `engagement`) | `GET/PUT /settings` | Build (designed here) |
| Survey builder | Shift Module UX 03 (live builder) | survey, survey_question, survey_option, survey_audience | `GET/POST /surveys`, `GET/PUT/DELETE /surveys/{id}` | Build: title, description, opening / closing date, anonymous or named, audience, questions of six types, required flag |
| Publish / close / move closing date | builder "Save"; closing date | survey.status | `PATCH /surveys/{id}/publish`, `/close`, `/closing-date` | Build |
| "Survey Available (n)" popup, Skip, Respond | Shift Module UX 03 | survey_participant, survey_response, survey_answer | `GET /my-surveys?filter=pending` (meta.total is n), `GET /my-surveys/{id}`, `POST /my-surveys/{id}/response`, `POST /my-surveys/{id}/skip` | Build |
| Results | none (builder "Preview" only) | survey_answer | `GET /surveys/{id}/results`, `GET /surveys/{id}/responses`, `GET /surveys/{id}/export` | Build: totals per question; named answers per person; CSV |
| Builder "Preview" | live builder | — | `GET /surveys/{id}` | Client-side: the survey with its questions is all a preview needs |
| Announcements, notice board, events | App Version "Announcements" | announcement, announcement_read | `/api/organisation/announcements` | Unchanged (Organisation module). Read marks (`announcement_read`) still have no endpoint |
| Notifications | App Version "Notifications" | core.notification | `/api/inbox/...` | Engagement adds inbox rows (type `engagement`) |

34 endpoints: newsfeed 14, moderation 3, settings 2, surveys (HR) 11, answering 4. Tests: 13
(`tests/test_engagement_feed.py` 8, `tests/test_engagement_surveys.py` 5).

## ERD changes (erd/source/14-eng.md) and why

- `post`: `visibility` is now public / department / branch (was public / department / team) with
  `department_id` / `branch_id` as the target; `is_pinned`, `pinned_at`, `pinned_by_user_id`; `is_hidden`,
  `hidden_at`, `hidden_by_user_id`, `hidden_reason`; `deleted_at`, `deleted_by_user_id` next to `is_deleted`.
  Body optional (a post may be photos only).
- `post_media`: UNIQUE (post_id, file_id); `media_type` photo / video, set from the file's type.
- `post_reaction.reacted_at`, `post_comment.commented_at`, `post_comment_like.liked_at`, `post_view.viewed_at`
  NOT NULL. `post_comment.edited_at` added.
- New `post_mention` (post or comment, employee).
- `survey`: `description`, `is_anonymous`, `opens_on`, `published_at` / `_by`, `closed_at` / `_by`;
  status draft / published / closed.
- New `survey_audience` (department, branch or employee rows; none = everyone).
- `survey_question`: `is_required`, `scale_min`, `scale_max`, `scale_min_label`, `scale_max_label`;
  question_type single, dropdown, multiple, text, paragraph, rating.
- `survey_option.sort_order`.
- New `survey_participant` (survey, employee, responded_at, skipped, skipped_at): who answered or skipped.
  `survey_response.skipped` moved here; `survey_response.employee_id` is blank for anonymous surveys.
- `survey_answer.rating_value` (Linear Scale).
- `announcement` and `announcement_read`: unchanged, so `eng.usp_announcement*` keep working.

## Decisions

| # | Decision | Why |
|---|---|---|
| 1 | Audience: public (whole company), department (that department and its sub-departments), branch. Authors always see their own posts. | The design shows a "Public" chip, so there are other audiences; department and branch are the units HR works with. |
| 2 | Staff post to everyone, to their own department or a department above it, or to their own branch. Moderators (`engagement.moderation.edit`) post to any department or branch. | Stops people broadcasting into other teams' feeds. |
| 3 | Company setting `who_may_post`: everyone (anyone with `engagement.feed.create`) or moderators only. Staff keep commenting and reacting. Also `allow_comments` and `max_media_per_post` (default 10, 1–20). | Employers differ on open newsfeeds. |
| 4 | Moderators: whoever holds `engagement.moderation.*`, over the authors their scope reaches (`auth.fn_visible_employees`); company scope = everyone. They see every post of those authors (any audience, hidden too), pin / unpin, hide / show (with a reason; the author is told), delete posts and comments (the author is told when a post is removed). They do not edit other people's words. | HR must be able to take content down; editing someone's post would put words in their mouth. |
| 5 | A hidden post: only its author and moderators see it; no new reactions or comments; hiding unpins it; it cannot be pinned. | |
| 6 | Deleting a post marks it deleted (kept with who and when, audit log entry); comments are deleted for real with their replies, likes and mentions. | NFR-3 / NFR-4 style trace for posts; comments carry less weight. |
| 7 | Only the author edits a post or comment (`edited_at` shown); deleting: the author (`engagement.feed.delete`) or a moderator (`engagement.moderation.delete`). The post's author cannot delete other people's comments on it. | Matches My Posts (Edit Post, Delete) and the PM rule "edit only their own". |
| 8 | Replies are one level deep: a reply to a reply joins the same thread (Facebook style). | The design shows Reply under comments, no deeper nesting. |
| 9 | Reactions: one per person per post, six kinds; changing it does not notify again. Comment likes are plain likes. | "Reactions on Post" vs "Like" on a comment in the design. |
| 10 | Views: the app calls `POST /posts/{id}/view` when a post is shown; counted once per person; authors' own views and users without an employee record are not counted. | A list read is not a view; "2.5k Views" counts people. |
| 11 | Notifications (inbox, type `engagement`, link to the post): the post's author on a new comment or reaction, the comment's author on a reply or a like, mentioned people when first mentioned; nobody about their own action and nobody twice for one comment. Mentioned people must be able to read the post (422 otherwise), so a mention never leaks a department-only post. | |
| 12 | Posting, reacting and commenting need an employee record (403 otherwise); a user without one (e.g. the first administrator) reads public posts and moderates. | Every post, reaction and comment belongs to an employee in the ERD. |
| 13 | Feed order: pinned first (in the feed only), then newest. My Posts and the moderation list: newest first. Paging `page` / `pageSize` as everywhere. | |
| 14 | Surveys are edited only as drafts (questions, options, audience replaced in one call); once published only the closing date moves; answered surveys are closed, not deleted (409 `SURVEY_HAS_RESPONSES`). | Changing questions under people who answered would corrupt results. |
| 15 | A survey is open when published, its opening date (default: publish day) has come and its closing date (optional) has not passed. A published survey past its closing date reads as closed everywhere. | No scheduler is needed. |
| 16 | Audience: departments (with sub-departments), branches and people, combined; none = everyone; people who left or were switched off are not asked. It is evaluated live, so a new joiner in the audience sees an open survey. | |
| 17 | One response per person, final once sent (no edit). Skipping is not final: a skipped survey can still be answered while open. my-surveys statuses: pending, skipped, answered, missed. | The popup has Skip and Respond; "one response per employee". |
| 18 | Anonymous surveys: the response row holds no employee, no `created_by`, and its time is cut to the day; `survey_participant` alone records that someone answered (so the one-response rule still holds). Results and the export never name anyone; the per-person answers endpoint refuses (403 `SURVEY_ANONYMOUS`); the response event carries no employee. | Real anonymity, not just hidden names. |
| 19 | Question types map the builder: Multiple Choice = `single`, Dropdown = `dropdown` (single answer), Check Boxes = `multiple`, Short Answer = `text` (500), Paragraph = `paragraph` (5000), Linear Scale = `rating` (from 0 or 1 to 2–10, end labels). Choice questions need two distinct options. Up to 100 questions. | |
| 20 | Results: per question the number who answered, each option's count and share of those who answered, rating average and distribution, the newest 100 text answers (no names). Response rate = answered / audience now. | |
| 21 | Publishing tells everyone in the audience in the inbox ("Survey available: <title>"), link `/engagement/my-surveys/{id}`. | The popup is the in-app equivalent; mail is not built. |

## Permissions (app/catalogue/engagement.py)

| Code | Actions | Used for |
|---|---|---|
| `engagement.feed` | view, create, edit, delete | read the feed and My Posts; post, react, comment, like; edit own; delete own |
| `engagement.moderation` | view, edit, delete | moderation list; pin / hide; delete anyone's post or comment (scope = whose) |
| `engagement.surveys` | view, create, edit, delete, publish, close, export | the survey screens and results |
| `engagement.survey_responses` | view, respond | read named answers per person (scope = whose); answer surveys addressed to you |
| `engagement.settings.general` | view, edit | the settings above |

Proposed default-role grants (`app/core/default_roles.py`, owned elsewhere): the Employee role, and the
self-service part of Line Manager and Department Head, should hold `engagement.feed.view/create/edit/delete`
and `engagement.survey_responses.respond` with own scope; today staff hold no engagement code, so tests grant
them per user (`tests/factories_engagement.py`). HR Manager and Company Administrator get everything through
their patterns; HR Officer gets everything except deletes and settings (so it moderates by pinning and
hiding but does not delete); Executive gets the `.view` codes.

## Events (EVENTS in app/catalogue/engagement.py)

`engagement.post_published`, `engagement.post_deleted`, `engagement.post_hidden`, `engagement.comment_added`,
`engagement.survey_published`, `engagement.survey_closed`, `engagement.survey_response_submitted`.
Every inbox notification is also `notification.created`. Reactions and likes publish no event of their
own (too frequent to be useful to an outside system; their notifications are events already).

## Gaps both ways

- Documents without a build: announcement "Mark as read / Mark all as read / Clear All" (`announcement_read`)
  has no endpoint yet (Organisation module's announcements); survey "Preview" is client-side.
- Built without a design: moderation, settings, survey results, named answers, export, anonymous surveys,
  audiences, closing-date changes.
- Not built: sharing a post outside the company, reposts, polls inside posts, hashtags, post scheduling,
  editing a sent survey answer, survey templates, reminders to people who have not answered, scoring.
- Anonymity limit: `survey_participant.responded_at` and the response's insert order could in principle be
  matched by someone with database access in a tiny audience; the API never does. A minimum audience size
  for showing results is not enforced.
- Feed performance: the feed computes the reader's audience on each request; an index on
  `eng.post (company_id, is_deleted, posted_at)` would help at scale (the ERD script makes FK and UNIQUE
  indexes only).
- Publishing to a large audience adds one notification per person inside the publish transaction.

## Cross-module needs

- `app/core/default_roles.py`: the staff grants above.
- Inbox / mobile: open `link` values `/engagement/posts/{id}`, `/engagement/my-posts`, `/engagement/my-surveys/{id}`.
- Files: photos and videos are uploaded with `module=engagement`; videos rely on the file service's mp4 / mov / webm
  types and `MAX_UPLOAD_MB` (videos may need a larger limit than documents).
- Organisation: announcement read marks (`announcement_read`) when the Notice Board needs them.
- Dashboards: an "Employee engagement" widget could read `/my-surveys?filter=pending` (count) and the feed.
