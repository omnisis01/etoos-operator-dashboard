# 상담일지 퇴원 어댑터 — 퇴원_N수 + 퇴원_윈터 → 정규화·집계 (프로토타입)
from pyxlsb import open_workbook
from datetime import datetime, timedelta
from collections import Counter, defaultdict
import json, re, unicodedata, sys

F=sys.argv[1] if len(sys.argv)>1 else "이투스 247 대치점 상담일지 2026.06.22_강팀장 공유본.xlsb"
def ser2date(v):
    try:
        f=float(v)
        if 20000<f<60000: return datetime(1899,12,30)+timedelta(days=f)
    except: pass
    return None
def norm(s):
    if s is None: return ""
    s=unicodedata.normalize('NFC',str(s)).strip().strip('`').replace('　','').strip()
    return s
# 표준 코드 사전
MAJOR={'입시환경':'ENV','개인환경':'PERSONAL','제적':'EXPELLED','기타환경':'ETC','생활시설환경':'FACILITY'}
MINOR={
 '등원전환불':'NO_SHOW_REFUND','타학원이동':'MOVE_OTHER_ACADEMY','타학원 이동':'MOVE_OTHER_ACADEMY',
 '타247이동':'MOVE_247','통학거리':'DISTANCE','독학':'SELF_STUDY','독학(집)':'SELF_STUDY','독학(독서실)':'SELF_STUDY',
 '건강악화':'HEALTH','재수포기':'QUIT_REEXAM','학원부적응':'MALADJUST','기숙학원이동':'MOVE_BOARDING',
 '기숙학원':'MOVE_BOARDING','등원시기 고민':'TIMING','기타':'ETC',
 '독서실':'SELF_STUDY','추가합격':'ADMIT','수시합격':'ADMIT','수시합격(자퇴)':'ADMIT','대학교합격':'ADMIT','대학교추가합격':'ADMIT','대학복학':'ADMIT',
 '수시준비':'ADMIT_PREP','실기준비':'ADMIT_PREP','가정형편':'PERSONAL','부모님반대':'PERSONAL','개인성적 불만':'PERSONAL',
 '이사':'DISTANCE','통학거리(이사)':'DISTANCE','유학':'ABROAD','급식문제':'FACILITY',
}
LABEL={'NO_SHOW_REFUND':'등원 전 환불','MOVE_OTHER_ACADEMY':'타학원 이동','MOVE_247':'타 247 이동','DISTANCE':'통학거리',
 'SELF_STUDY':'독학 전환','HEALTH':'건강 악화','QUIT_REEXAM':'재수 포기','MALADJUST':'학원 부적응','MOVE_BOARDING':'기숙학원 이동',
 'TIMING':'등원시기 고민','ETC':'기타','ADMIT':'합격·진학','ADMIT_PREP':'수시·실기 준비','ABROAD':'유학','UNMAPPED':'미분류'}
MAJLABEL={'ENV':'입시환경','PERSONAL':'개인환경','EXPELLED':'제적','ETC':'기타환경','FACILITY':'생활시설','UNMAPPED':'미분류'}

wb=open_workbook(F)
rows=[]; unmapped=Counter()
for sheet in ['퇴원_N수','퇴원_윈터']:
    season_default = '윈터' if '윈터' in sheet else None
    with wb.get_sheet(sheet) as sh:
        for i,row in enumerate(sh.rows()):
            if i<3: continue
            v=[c.v for c in row]
            if len(v)<10 or not v[1]: continue
            name=norm(v[1])
            if name in ('','학생이름') or '합계' in name: continue
            d=ser2date(v[3])  # 실제퇴원일
            classname=norm(v[5])
            season = '윈터' if '윈터' in classname else ('조기선발' if '조기선발' in classname else ('정규' if '정규' in classname else (season_default or 'N수')))
            maj=norm(v[7]); mino=norm(v[8])
            mc=MAJOR.get(maj,'UNMAPPED'); nc=MINOR.get(mino,'UNMAPPED')
            if nc=='UNMAPPED' and mino: unmapped[mino]+=1
            rows.append({'sheet':sheet,'season':season,'date':d.strftime('%Y-%m') if d else None,
                         'year':d.year if d else None,'major':mc,'minor':nc,'minor_raw':mino,'sex':norm(v[11]) if len(v)>11 else ''})

total=len(rows)
by_minor=Counter(r['minor'] for r in rows)
by_major=Counter(r['major'] for r in rows)
by_season=Counter(r['season'] for r in rows)
by_month=Counter(r['date'] for r in rows if r['date'])
# 최근 12개월
months=sorted([m for m in by_month if m], reverse=True)[:12][::-1]
agg={
 'total':total,
 'major':[{'code':c,'label':MAJLABEL.get(c,c),'count':n,'pct':round(n/total*100,1)} for c,n in by_major.most_common()],
 'minor':[{'code':c,'label':LABEL.get(c,c),'count':n,'pct':round(n/total*100,1)} for c,n in by_minor.most_common(10)],
 'season':[{'season':s,'count':n} for s,n in by_season.most_common()],
 'recent_months':[{'month':m,'count':by_month[m]} for m in months],
 'unmapped':dict(unmapped.most_common()),
}
json.dump(agg, open("DATA pipeline/out/withdrawal_reasons.json","w",encoding='utf-8'), ensure_ascii=False, indent=2)
print(f"총 퇴원 {total}건")
print("대분류:", [(x['label'],x['count']) for x in agg['major']])
print("소분류 TOP:", [(x['label'],x['count'],str(x['pct'])+'%') for x in agg['minor']])
print("시즌:", [(x['season'],x['count']) for x in agg['season']])
print("최근월:", [(x['month'],x['count']) for x in agg['recent_months'][-6:]])
print("UNMAPPED:", agg['unmapped'])
