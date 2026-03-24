export interface Circle {
  id: string;
  name: string;
  invite_code: string;
  created_by_user_id: string;
  created_at: Date;
  updated_at: Date;
}

export interface CircleMember {
  id: string;
  circle_id: string;
  user_id: string;
  role: 'owner' | 'member';
  joined_at: Date;
}

export interface CircleWithMemberCount extends Circle {
  member_count: number;
}
