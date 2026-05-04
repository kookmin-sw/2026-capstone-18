resource "aws_secretsmanager_secret" "supabase" {
  name                    = "${local.name_prefix}/supabase"
  description             = "Supabase project URL, anon key, service-role key, JWT secret, Google OAuth client ID. Populated manually post-apply."
  recovery_window_in_days = 7
}
