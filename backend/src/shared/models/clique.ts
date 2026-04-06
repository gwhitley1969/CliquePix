export interface Clique {
  id: string;
  name: string;
  invite_code: string;
  created_by_user_id: string;
  created_at: Date;
  updated_at: Date;
}

export interface CliqueMember {
  id: string;
  clique_id: string;
  user_id: string;
  role: 'owner' | 'member';
  joined_at: Date;
}

export interface CliqueWithMemberCount extends Clique {
  member_count: number;
}
