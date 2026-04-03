-- Add 'event_deleted' to notifications type CHECK constraint
ALTER TABLE notifications DROP CONSTRAINT notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
  CHECK (type IN ('new_photo', 'event_expiring', 'event_expired', 'member_joined', 'event_deleted'));
