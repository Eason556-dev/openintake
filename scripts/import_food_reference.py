#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rebuild read-only reference DB from official FDC SR Legacy April 2018 CSV zip.
Usage: python3 scripts/import_food_reference.py /path/to/archive.zip
No API key or network access. Nutrients not explicitly mapped remain unavailable.
"""
import csv, hashlib, io, json, sqlite3, sys, zipfile
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
# USDA nutrient IDs, not nutrient numbers. RAE/DFE/IU are deliberately not treated as mass.
MAPPING = {'1003':'protein','1004':'fatTotal','1005':'carbohydrates','1008':'energyConsumed','1079':'fiber','2000':'sugar','1087':'calcium','1089':'iron','1090':'magnesium','1091':'phosphorus','1092':'potassium','1093':'sodium','1095':'zinc','1096':'chromium','1098':'copper','1100':'iodine','1101':'manganese','1102':'molybdenum','1103':'selenium','1109':'vitaminE','1114':'vitaminD','1162':'vitaminC','1165':'thiamin','1166':'riboflavin','1167':'niacin','1170':'pantothenicAcid','1175':'vitaminB6','1176':'biotin','1177':'folate','1178':'vitaminB12','1185':'vitaminK','1253':'cholesterol','1057':'caffeine','1258':'fatSaturated','1292':'fatMonounsaturated','1293':'fatPolyunsaturated'}
# Search aliases only: never nutrition profiles or automatic generic beef substitutions.
ALIASES = {
 "169757": ["熟白米饭（未加盐、未强化）", "米饭", "白米饭", "熟米饭", "cooked rice", "cooked white rice", "rice", "white rice"],
 "169756": ["生白长粒米（未强化）", "生米", "大米", "raw rice", "raw white rice", "rice", "white rice"],
 "171793": ["煎熟瘦牛肉饼（90%瘦肉）", "熟牛肉", "熟牛肉饼", "cooked beef", "牛肉", "beef"],
 "171794": ["煎熟瘦牛肉末（90%瘦肉）", "熟牛肉", "熟牛肉末", "cooked beef", "牛肉", "beef"],
 "174030": ["生牛肉末（90%瘦肉）", "生牛肉", "牛肉", "raw beef", "beef"],
 "173944": ["香蕉", "banana", "bananas"],
 "171688": ["苹果", "带皮苹果", "apple"],
 "170379": ["生西兰花", "西兰花"],
 "171287": ["生鸡蛋", "鸡蛋"],
 "171265": ["全脂牛奶（添加维生素D）", "牛奶", "全脂牛奶"],
 "172217": ["全脂牛奶（未添加维生素A或D）", "牛奶", "全脂牛奶"],
 "171477": ["烤鸡胸肉", "熟鸡胸肉"],
 "170393": ["生胡萝卜", "胡萝卜"],
 "170457": ["西红柿", "番茄"],
 "168462": ["生菠菜", "菠菜"],
 "169249": ["生菜"],
 "167762": ["草莓"],
 "171413": ["橄榄油"],
 "169655": ["白砂糖"],
 "173468": ["食盐"],
 "169737": ["熟意大利面"],
 "173424": ["水煮全蛋", "鸡蛋", "水煮蛋"],
 "172187": ["炒全蛋", "鸡蛋", "炒鸡蛋"],
 "169339": ["水煮胡萝卜（加盐）", "胡萝卜"],
 "168510": ["水煮西兰花（加盐）", "西兰花"],
 "170531": ["水煮菠菜（加盐）", "菠菜"],
}

LOCAL_ONLY = {'1235':('addedSugars','g'),'1106':('vitaminARAE','mcg RAE'),'1190':('folateDFE','mcg DFE'),'1051':('foodMoisture','g')}

def main(path):
 archive=Path(path)
 expected="b80817294b8850530aaedf2e515c02593b1824f763a0ff356e5c2081643e6fd0"
 if hashlib.sha256(archive.read_bytes()).hexdigest()!=expected:raise ValueError("Archive hash differs from the reviewed USDA SR Legacy download; review/version the importer before replacing data")
 z=zipfile.ZipFile(archive)
 def rows(name):return csv.DictReader(io.TextIOWrapper(z.open(next(n for n in z.namelist() if n.split('/')[-1]==name)),encoding='utf-8-sig'))
 definitions={r['id']:r for r in rows('nutrient.csv')}
 units={key:r['unit_name'].lower() for key,r in definitions.items()}
 # Protect against confusing nutrient IDs with nutrient numbers or adjacent fatty acids.
 assert definitions['1057']['name']=='Caffeine' and units['1057']=='mg'
 assert definitions['1257']['name']=='Fatty acids, total trans'
 assert definitions['1008']['name']=='Energy' and units['1008']=='kcal'
 assert definitions['1096']['name']=='Chromium, Cr' and units['1096']=='ug'
 foods={r['fdc_id']:r for r in rows('food.csv')}
 categories={r['id']:r['description'] for r in rows('food_category.csv')}
 nutrition={};portions={};extras={}
 for r in rows('food_nutrient.csv'):
  key=MAPPING.get(r['nutrient_id']);unit=units.get(r['nutrient_id'])
  if r['nutrient_id'] in LOCAL_ONLY and r['amount']:
   name,display_unit=LOCAL_ONLY[r['nutrient_id']]
   extras.setdefault(r['fdc_id'],[]).append({'id':name,'value':float(r['amount']),'unit':display_unit})
  if key and unit in ['g','mg','ug','kcal'] and r['amount']:
   value=float(r['amount'])
   if value>=0:nutrition.setdefault(r['fdc_id'],[]).append([key,str(value),'mcg' if unit=='ug' else unit])
 for r in rows('food_portion.csv'):
  if r['gram_weight'] and r['amount'] and float(r['amount'])>0 and r['modifier']:
   portions.setdefault(r['fdc_id'],[]).append({'name':r['modifier'],'grams':float(r['gram_weight'])/float(r['amount'])})
 out=ROOT/'Sources/IntakeCore/Resources/FoodReference.sqlite';out.unlink(missing_ok=True)
 db=sqlite3.connect(out);db.executescript('CREATE TABLE food(id TEXT PRIMARY KEY,name TEXT NOT NULL,aliases TEXT NOT NULL,search TEXT NOT NULL,nutrients TEXT NOT NULL,servings TEXT NOT NULL,extras TEXT NOT NULL,category TEXT NOT NULL); CREATE INDEX food_name ON food(name COLLATE NOCASE); CREATE VIRTUAL TABLE food_search USING fts5(id UNINDEXED, search, tokenize=unicode61); CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT);')
 for fid,r in foods.items():
  aliases=ALIASES.get(fid,[]);name=r['description']
  db.execute('INSERT INTO food VALUES(?,?,?,?,?,?,?,?)',(fid,name,json.dumps(aliases,ensure_ascii=False),' '.join([name]+aliases).lower(),json.dumps(nutrition.get(fid,[]),separators=(',',':')),json.dumps(portions.get(fid,[])),json.dumps(extras.get(fid,[])),categories.get(r['food_category_id'],'')))
 for fid,r in foods.items():db.execute('INSERT INTO food_search VALUES(?,?)',(fid,' '.join([r['description']]+ALIASES.get(fid,[]))))
 metadata={'source':'USDA FoodData Central — SR Legacy','version':'April 2018 / publication 2019-04-01','archiveSHA256':hashlib.sha256(archive.read_bytes()).hexdigest(),'license':'CC0-1.0','sourceURL':'https://fdc.nal.usda.gov/download-datasets/','foodCount':str(len(foods)),'mapping':json.dumps(MAPPING,sort_keys=True),'appOnly':json.dumps(LOCAL_ONLY,sort_keys=True)}
 db.executemany('INSERT INTO metadata VALUES(?,?)',metadata.items());db.commit();db.execute('VACUUM');db.close()
 (ROOT/'docs/food-reference-manifest.json').write_text(json.dumps(metadata,indent=2)+'\n')
 print(f'Imported {len(foods)} foods; {out.stat().st_size} bytes')
if __name__=='__main__':main(sys.argv[1])
