# 모여 — 다중 사용자 커뮤니티

다크 모드 한국어 커뮤니티입니다. 프런트엔드는 단일 `index.html`이며 Supabase를 백엔드로 사용합니다.

## 기능
- 이메일 회원가입/로그인, 프로필 닉네임
- 게시글 작성/수정/삭제, 게시판 분류, 검색
- 댓글 및 대댓글, 추천, 인기순 정렬
- 이미지 첨부 (5MB 제한)
- 신고 접수 및 관리자 권한용 데이터 정책

## 1. Supabase 프로젝트 준비
1. https://supabase.com 에서 새 프로젝트를 만듭니다.
2. 프로젝트의 **SQL Editor**를 열고 `supabase-setup.sql` 내용을 붙여넣어 실행합니다.
3. **Project Settings → API** (또는 Connect 화면)에서 Project URL과 publishable/anon key를 복사합니다.
4. `index.html`을 편집해 다음 두 줄의 값을 교체합니다.
   - `YOUR_SUPABASE_URL` → 프로젝트 URL
   - `YOUR_SUPABASE_ANON_KEY` → publishable/anon key (또는 anon public key)
5. `service_role` / secret key는 절대로 HTML에 넣거나 공개하지 마세요.

## 2. 이메일 로그인 설정
Supabase Dashboard → Authentication → URL Configuration에서 개발 중 사용할 사이트 URL을 설정합니다. 배포 후에는 실제 배포 URL을 추가합니다. 이메일 확인을 켰다면 가입자가 받은 메일에서 확인해야 로그인할 수 있습니다.

## 3. 실행
- 간단히 `index.html`을 열어 UI를 확인할 수 있지만, 브라우저/인증 리다이렉트 제한을 피하려면 로컬 웹 서버를 권장합니다.
- PC에 Python이 있다면 폴더에서 터미널을 열고 실행:
  `python -m http.server 8000`
- 브라우저에서 `http://localhost:8000` 접속합니다.
- 인터넷에 공개하려면 GitHub Pages, Netlify, Vercel 등의 정적 호스팅에 `index.html`을 배포합니다. URL을 Supabase Auth의 허용 URL에 추가하세요.

## 4. 관리자 설정
1. 먼저 사이트에서 관리자 계정으로 쓸 이메일을 회원가입합니다.
2. Supabase → SQL Editor에서 아래 SQL을 이메일을 바꿔 실행합니다.
   ```sql
   update public.profiles p
   set role='admin'
   from auth.users u
   where p.id=u.id and u.email='관리자이메일@example.com';
   ```
3. 로그아웃 후 다시 로그인하면 관리자 표시가 나타납니다. 관리자 권한은 데이터베이스에서 확인합니다.

## 꼭 알아둘 점 / 제한
- 이 프로젝트는 실제 DB를 사용하는 시작용 구현입니다. **설정하지 않은 상태에서는 서버에 연결되지 않습니다.**
- 관리자 신고함에서 접수된 신고를 확인하고 검토 완료/기각 상태로 변경할 수 있습니다.
- 공개 이미지 URL은 게시글에서 누구나 볼 수 있습니다. 민감한 사진을 올리지 마세요.
- 운영 전에 이메일 인증, 비밀번호 정책, 스팸/도배 방지, rate limit, 개인정보 처리방침, 서비스 약관, 백업, 로그/모니터링, 신고 처리 절차를 추가하세요.
- SQL은 시작용입니다. 출시 전에는 RLS 정책을 검토하고, 닉네임 중복/비속어 방지와 이미지 삭제/교체 처리도 추가하는 것이 좋습니다.
- 프런트엔드에는 공개 가능한 anon/publishable key만 둡니다. `service_role` 키를 브라우저 코드에 절대 넣지 마세요.
