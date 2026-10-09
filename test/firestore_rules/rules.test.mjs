// เทส firestore.rules บน Firestore emulator: ทุกรูปแบบที่แอป (และสคริปต์ใน tool/) เขียน
// ต้องผ่าน และข้อมูลผิดต้องถูกปฏิเสธ — วิธีรันดู README.md ในโฟลเดอร์นี้
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc, deleteDoc, getDoc, writeBatch, setLogLevel } from 'firebase/firestore';

setLogLevel('error');
let env;
const U = 'alice';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-energy-home',
    firestore: { rules: readFileSync(fileURLToPath(new URL('../../firestore.rules', import.meta.url)), 'utf8'), host: '127.0.0.1', port: 8080 },
  });
});
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const db = () => env.authenticatedContext(U).firestore();
const other = () => env.authenticatedContext('bob').firestore();
const anon = () => env.unauthenticatedContext().firestore();
const seed = (path, data) => env.withSecurityRulesDisabled((c) => setDoc(doc(c.firestore(), path), data));

const user = {
  uid: U, name: 'Alice', email: 'a@example.com', area: 'bangkok', meterType: 'normal',
  electricityTariff: 'standard', billingDay: 30, fixedCost: 0,
  startElectricityValue: 0, startWaterValue: 0, startPeakValue: 0, startOffPeakValue: 0,
  startBillingMonth: 0, startBillingYear: 0, startMeterConfigured: false,
  electricityStartConfigured: false, waterStartConfigured: false, billingDayConfigured: false,
};
const bill = {
  id: 'b1', uid: U, year: 2026, month: 9, electricityUsed: 320.5, electricityPeakUsed: 0,
  electricityOffPeakUsed: 0, waterUsed: 18, electricityCost: 1257.85, waterCost: 180.2,
  fixedCost: 500, totalCost: 1938.05, source: 'compiled', yearMonth: 202609,
};
const eLog = {
  id: 'e1', uid: U, date: '2026-09-05T20:00:00.000', meterValue: 14100.5, peakMeterValue: null,
  offPeakMeterValue: null, usedFromStart: 91.5, usedFromLast: 30, cost: 412.3,
};
const touLog = { ...eLog, id: 'e2', meterValue: 120, peakMeterValue: 5021.2, offPeakMeterValue: 8800.1 };
const wLog = { id: 'w1', uid: U, date: '2026-09-05T20:00:00.000', meterValue: 148.2, usedFromStart: 4, usedFromLast: 4, cost: 60 };
const record = {
  id: 'r1', uid: U, electricityValue: 14009, waterValue: 148, peakValue: 0, offPeakValue: 0,
  billingMonth: 9, billingYear: 2026, recordedAt: '2026-09-30T09:00:00.000',
};
const fixed = {
  id: 'f1', uid: U, name: 'อินเทอร์เน็ต', category: 'internet', amount: 599,
  createdAt: '2026-09-01T10:00:00.000', startDate: '2026-09-01T00:00:00.000', endDate: null,
};
const appliance = {
  id: 'a1', uid: U, name: 'แอร์ห้องนอน', watt: 1200, iconKey: 'air_conditioner',
  schedules: [{ days: [0, 1, 2, 3, 4, 5, 6], startTime: '00:00', endTime: '08:00' }],
};

// ---------- what the app writes must pass ----------

test('user doc: create, partial updates the app makes, read, delete', async () => {
  const ref = doc(db(), `users/${U}`);
  await assertSucceeds(setDoc(ref, user));
  await assertSucceeds(updateDoc(ref, { name: 'Alice B' }));
  await assertSucceeds(updateDoc(ref, { billingDay: 15, billingDayConfigured: true }));
  await assertSucceeds(updateDoc(ref, {
    startBillingMonth: 9, startBillingYear: 2026, startElectricityValue: 14009.5,
    startPeakValue: 0, startOffPeakValue: 0, electricityStartConfigured: true,
    startWaterValue: 148, waterStartConfigured: true, startMeterConfigured: true,
  }));
  await assertSucceeds(updateDoc(ref, { electricityTariff: 'small' }));
  await assertSucceeds(updateDoc(ref, { fixedCost: 1099 }));
  // clearing the start reading writes zeros
  await assertSucceeds(updateDoc(ref, { startBillingMonth: 0, startBillingYear: 0, startElectricityValue: 0, startMeterConfigured: false }));
  await assertSucceeds(getDoc(ref));
  await assertSucceeds(deleteDoc(ref));
});

test('subcollections: every model toMap() shape is accepted', async () => {
  const f = db();
  await assertSucceeds(setDoc(doc(f, `users/${U}/bills/b1`), bill));
  await assertSucceeds(setDoc(doc(f, `users/${U}/bills/b2`), { ...bill, id: 'b2', source: 'startMeter', electricityPeakUsed: 100, electricityOffPeakUsed: 220.5 }));
  await assertSucceeds(setDoc(doc(f, `users/${U}/electricity_logs/e1`), eLog));
  await assertSucceeds(setDoc(doc(f, `users/${U}/electricity_logs/e2`), touLog));
  await assertSucceeds(setDoc(doc(f, `users/${U}/water_logs/w1`), wLog));
  await assertSucceeds(setDoc(doc(f, `users/${U}/start_meter_history/r1`), record));
  await assertSucceeds(setDoc(doc(f, `users/${U}/fixed_costs/f1`), fixed));
  await assertSucceeds(setDoc(doc(f, `users/${U}/fixed_costs/f2`), { ...fixed, id: 'f2', endDate: '2026-12-31T00:00:00.000' }));
  await assertSucceeds(setDoc(doc(f, `users/${U}/appliances/a1`), appliance));
  await assertSucceeds(setDoc(doc(f, `users/${U}/appliances/a2`), (({ iconKey, ...a }) => ({ ...a, id: 'a2' }))(appliance)));
  // overwrite with set (saveBill, compileBill backfill)
  await assertSucceeds(setDoc(doc(f, `users/${U}/bills/b1`), { ...bill, source: 'imported', totalCost: 2000 }));
});

test('batched partial updates the app makes (recalc, tariff change, delete log)', async () => {
  await seed(`users/${U}/electricity_logs/e1`, eLog);
  await seed(`users/${U}/electricity_logs/e2`, touLog);
  await seed(`users/${U}/water_logs/w1`, wLog);
  const f = db();
  const b = writeBatch(f);
  b.update(doc(f, `users/${U}/electricity_logs/e1`), { cost: 380.25 });
  b.update(doc(f, `users/${U}/electricity_logs/e2`), { meterValue: 140, usedFromStart: 140, cost: 600 });
  b.update(doc(f, `users/${U}/water_logs/w1`), { usedFromStart: 6, cost: 75 });
  await assertSucceeds(b.commit());
  const d = writeBatch(f);
  d.delete(doc(f, `users/${U}/electricity_logs/e1`));
  d.update(doc(f, `users/${U}/electricity_logs/e2`), { usedFromLast: 0 });
  await assertSucceeds(d.commit());
});

test('an old doc with an odd value can still be updated in other fields', async () => {
  await seed(`users/${U}/water_logs/w1`, { ...wLog, usedFromLast: -3 });
  await assertSucceeds(updateDoc(doc(db(), `users/${U}/water_logs/w1`), { cost: 70 }));
  await seed(`users/${U}`, { ...user, billingDay: 0 });
  await assertSucceeds(updateDoc(doc(db(), `users/${U}`), { name: 'Old account' }));
});

test('Ft config is read-only for signed-in users', async () => {
  await seed('app_config/electricity_rates', { ft_rate: 0.1623 });
  await assertSucceeds(getDoc(doc(db(), 'app_config/electricity_rates')));
  await assertFails(setDoc(doc(db(), 'app_config/electricity_rates'), { ft_rate: 0 }));
  await assertFails(getDoc(doc(anon(), 'app_config/electricity_rates')));
});

// ---------- access ----------

test('only the owner can read or write', async () => {
  await seed(`users/${U}`, user);
  await seed(`users/${U}/bills/b1`, bill);
  await assertFails(getDoc(doc(other(), `users/${U}`)));
  await assertFails(getDoc(doc(other(), `users/${U}/bills/b1`)));
  await assertFails(setDoc(doc(other(), `users/${U}/bills/b9`), { ...bill, id: 'b9' }));
  await assertFails(deleteDoc(doc(other(), `users/${U}/bills/b1`)));
  await assertFails(getDoc(doc(anon(), `users/${U}`)));
});

test('unknown subcollections are denied', async () => {
  await assertFails(setDoc(doc(db(), `users/${U}/secrets/x`), { a: 1 }));
  await assertFails(getDoc(doc(db(), `users/${U}/secrets/x`)));
});

// ---------- bad data ----------

test('user doc: bad values are rejected', async () => {
  await seed(`users/${U}`, user);
  const ref = doc(db(), `users/${U}`);
  for (const bad of [
    { area: 'mars' }, { meterType: 'smart' }, { electricityTariff: 'cheap' },
    { billingDay: 0 }, { billingDay: 32 }, { billingDay: 'x' }, { billingDay: 15.5 },
    { fixedCost: -1 }, { startElectricityValue: -5 }, { startWaterValue: '148' },
    { startBillingMonth: 13 }, { startMeterConfigured: 'yes' }, { name: 'x'.repeat(101) },
    { uid: 'bob' },
  ]) {
    await assertFails(updateDoc(ref, bad), JSON.stringify(bad));
  }
  await assertFails(setDoc(doc(db(), `users/${U}`), { ...user, uid: 'bob' }));
});

test('bills, logs, records, fixed costs, appliances: bad values are rejected', async () => {
  const f = db();
  const cases = [
    [`bills/b1`, { ...bill, totalCost: -10 }],
    [`bills/b1`, { ...bill, month: 13 }],
    [`bills/b1`, { ...bill, source: 'hacked' }],
    [`bills/b1`, { ...bill, electricityUsed: 'many' }],
    [`bills/b1`, { ...bill, uid: 'bob' }],
    [`bills/b1`, { ...bill, id: 'other' }],
    [`electricity_logs/e1`, { ...eLog, meterValue: -1 }],
    [`electricity_logs/e1`, { ...eLog, cost: 1e12 }],
    [`electricity_logs/e1`, { ...eLog, usedFromLast: -2 }],
    [`electricity_logs/e1`, { ...eLog, peakMeterValue: 'abc' }],
    [`water_logs/w1`, { ...wLog, usedFromStart: -4 }],
    [`start_meter_history/r1`, { ...record, billingMonth: 0 }],
    [`start_meter_history/r1`, { ...record, waterValue: -148 }],
    [`fixed_costs/f1`, { ...fixed, amount: -599 }],
    [`fixed_costs/f1`, { ...fixed, name: 'x'.repeat(101) }],
    [`appliances/a1`, { ...appliance, watt: -100 }],
    [`appliances/a1`, { ...appliance, schedules: 'always' }],
    [`bills/b1`, { ...bill, ...Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`junk${i}`, i])) }],
  ];
  for (const [path, data] of cases) {
    await assertFails(setDoc(doc(f, `users/${U}/${path}`), data), path + ' ' + JSON.stringify(data).slice(0, 80));
  }
});

test('partial update with a bad value is rejected', async () => {
  await seed(`users/${U}/electricity_logs/e1`, eLog);
  await assertFails(updateDoc(doc(db(), `users/${U}/electricity_logs/e1`), { cost: -1 }));
  await assertFails(updateDoc(doc(db(), `users/${U}/electricity_logs/e1`), { uid: 'bob' }));
});
