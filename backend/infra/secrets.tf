resource "aws_secretsmanager_secret" "supabase" {
  name                    = "${local.name_prefix}/supabase"
  description             = "Supabase project URL, anon key, service-role key, JWT secret, Google OAuth client ID. Populated manually post-apply."
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "firebase" {
  name                    = "${local.name_prefix}/firebase"
  description             = "Firebase service-account JSON for FCM push. Populated manually post-apply."
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "sentry" {
  name                    = "${local.name_prefix}/sentry"
  description             = "Sentry DSN for the FastAPI backend. Populated manually post-apply via console or CLI."
  recovery_window_in_days = 7
}
