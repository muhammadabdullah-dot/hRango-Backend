## 14. Engagement [eng]

Sources: the Figma "HRango Dashboard App Version" frames (Newsfeed, Create Post, Reactions on Post, Comment
written, My Posts, Announcements, Notifications; read 2026-10-19); the survey popup and the live "Create
Survey" builder (requirements/HRango - Shift Module UX, section 03); "Employee Engagement Feeds" in the
feature lists (requirements/HRango - UI design/All Dashboards/09-Assets-Website-and-Marketing). Decisions:
comparison/13-engagement.md.

Posts reach an audience: public (the whole company), department (that department and its sub-departments) or
branch. Moderators (engagement.moderation) pin, hide and delete; a hidden post is seen only by its author and
moderators. Anonymous surveys keep who answered (survey_participant) apart from the answers (survey_response
without an employee), so the answers cannot be traced back.

```
announcement                          "Announcements" list; the dashboards' Notice Board (kind notice) and Upcoming Events (kind event)
  id                PK
  company_id        FK company
  author_id         FK employee       optional: blank when posted by a user with no employee record
  kind                                notice, event
  title
  body
  event_date                          the day an event happens (kind event)
  publish_from, publish_to            shown between these dates; blank means from now / until removed

announcement_read                     "Mark as read" / "Mark all as read" / "Clear All", per employee
  announcement_id FK announcement, employee_id FK employee, read_at, cleared_at

post                                  newsfeed post ("What would you like to share?")
  id                PK
  company_id        FK company
  author_id         FK employee
  body                                text, up to 5000 characters; blank when the post is only photos or videos
  visibility                          public (chip "Public"), department, branch
  department_id     FK department     the audience when visibility is department (sub-departments included)
  branch_id         FK branch         the audience when visibility is branch
  posted_at
  edited_at                           "Edit Post" on My Posts
  is_pinned                           pinned posts open the feed
  pinned_at
  pinned_by_user_id FK user_account
  is_hidden                           hidden by a moderator: only the author and moderators see it
  hidden_at
  hidden_by_user_id FK user_account
  hidden_reason     {NVARCHAR(500)}
  is_deleted                          "Delete" on My Posts, or a moderator; kept for the audit trail
  deleted_at
  deleted_by_user_id FK user_account
  INDEX (company_id, is_deleted, posted_at)

post_media                            several photos and videos per post, in order
  id PK, post_id FK post, file_id FK stored_file, media_type, sort_order
  UNIQUE (post_id, file_id)

post_reaction                         "Liked" and the "Reactions on Post" list; one per person per post
  id PK, post_id FK post, employee_id FK employee, kind, reacted_at {NN}

post_comment                          comments with Reply (one level: a reply to a reply joins the same thread)
  id                PK
  post_id           FK post
  employee_id       FK employee
  parent_id         FK post_comment   the top-level comment a reply belongs to
  body                                up to 2000 characters
  commented_at      {NN}
  edited_at

post_comment_like                     "Like" on a comment
  post_comment_id FK post_comment, employee_id FK employee, liked_at {NN}

post_view                             "2.5k Views": counted once per person
  post_id FK post, employee_id FK employee, viewed_at {NN}

post_mention                          @person in a post (post_comment_id blank) or in a comment
  id PK, post_id FK post, post_comment_id FK post_comment, employee_id FK employee {NN}

survey                                survey builder: title, closing date, questions; "Survey Available" popup for the audience
  id                PK
  company_id        FK company
  title
  description
  is_anonymous                        answers are kept without the employee (survey_participant records who answered)
  status                              draft, published, closed (a published survey past its closing date reads as closed)
  opens_on          {DATE}            blank: from publishing
  closes_on                           last day to respond
  published_at
  published_by_user_id FK user_account
  closed_at
  closed_by_user_id FK user_account

survey_audience                       who is asked; no rows = everyone in the company
  id PK, survey_id FK survey, unit_type {NN}, unit_id {NN}
  UNIQUE (survey_id, unit_type, unit_id)

survey_question
  id                PK
  survey_id         FK survey
  sort_order
  question_type     {NN}              single (Multiple Choice), dropdown, multiple (Check Boxes), text (Short Answer), paragraph, rating (Linear Scale)
  question_text     {NN}              "What would you like to ask?"
  is_required
  scale_min         {INT}             rating: lowest value (0 or 1)
  scale_max         {INT}             rating: highest value (2 to 10)
  scale_min_label   {NVARCHAR(100)}
  scale_max_label   {NVARCHAR(100)}

survey_option                         "Add New Option"
  id PK, survey_question_id FK survey_question, sort_order, option_text {NN}

survey_participant                    one per employee per survey: answered or skipped ("Skip" on the popup)
  survey_id FK survey, employee_id FK employee, responded_at, skipped, skipped_at

survey_response                       the answers of one person; employee blank when the survey is anonymous
  id PK, survey_id FK survey, employee_id FK employee, submitted_at {NN}

survey_answer                         one row per chosen option, or one with the text or rating
  id PK, survey_response_id FK survey_response, survey_question_id FK survey_question {NN}, survey_option_id FK survey_option, answer_text, rating_value {INT}
```

```
announcement 1──* announcement_read
post 1──* post_media / post_reaction / post_comment / post_view / post_mention
post_comment 1──* post_comment (replies) / post_comment_like / post_mention
survey 1──* survey_audience / survey_question / survey_participant / survey_response
survey_question 1──* survey_option
survey_response 1──* survey_answer
```
