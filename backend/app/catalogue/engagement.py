"""Permission codes and events for Engagement: the company newsfeed and surveys.

Who reads a post is decided by the post's audience (public, department, branch), not by scopes: the
feed codes open the screens. Moderation codes are held with a scope: a moderator pins, hides and
deletes the posts and comments of the employees that scope reaches (company: everyone).
Announcements are under organisation.announcements.
"""

SCREENS: list[tuple[str, str, tuple[str, ...], bool]] = [
    ("engagement.feed", "Newsfeed and My Posts (posts, reactions, comments)", ("view", "create", "edit", "delete"), False),
    ("engagement.moderation", "Newsfeed moderation (pin, hide, delete anyone's posts and comments)",
     ("view", "edit", "delete"), False),
    ("engagement.surveys", "Surveys (builder, publishing, results)",
     ("view", "create", "edit", "delete", "publish", "close", "export"), False),
    ("engagement.survey_responses", "Survey answers (answering surveys, reading named answers)", ("view", "respond"), False),
    ("engagement.settings.general", "Engagement settings", ("view", "edit"), False),
]

EVENTS: list[tuple[str, str]] = [
    ("engagement.post_published", "A newsfeed post was published (author, audience, text, number of photos and videos)."),
    ("engagement.post_deleted", "A newsfeed post was deleted by its author or a moderator."),
    ("engagement.post_hidden", "A moderator hid a newsfeed post (reason)."),
    ("engagement.comment_added", "Someone commented on or replied in a newsfeed post."),
    ("engagement.survey_published", "A survey was published to its audience (title, closing date, audience size)."),
    ("engagement.survey_closed", "A survey was closed (answered and skipped counts)."),
    ("engagement.survey_response_submitted",
     "Someone answered a survey (the employee only for named surveys; never the answers)."),
]
