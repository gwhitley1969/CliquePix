-- Add age verification timestamp to users table.
-- Set when authVerify confirms the user passed the 13+ age check using
-- the dateOfBirth claim in their Entra access token. Null for users created
-- before the age gate was deployed (grandfathered) or when claim is absent.

ALTER TABLE users ADD COLUMN age_verified_at TIMESTAMPTZ;
