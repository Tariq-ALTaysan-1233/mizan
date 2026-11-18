const cards = [
  { title: 'إجمالي مصروفات المجموعة', value: '—', note: 'هذا الشهر', icon: '▤' },
  { title: 'ما دفعته', value: '—', note: 'مساهمتك الفعلية', icon: '◉' },
  { title: 'صافي مستحقاتك', value: '—', note: 'يظهر بعد تسجيل العمليات', icon: '⇄' },
  { title: 'الحسابات النشطة', value: '—', note: 'حساباتك الشخصية', icon: '▣' },
];
export default function Home() {
  return <main className="min-h-screen p-4 md:p-8">
    <div className="mx-auto max-w-7xl">
      <header className="mb-8 flex flex-wrap items-center justify-between gap-4">
        <div><div className="text-3xl font-black" style={{color:'var(--green)'}}>ميزان</div><p className="mt-1 text-sm text-gray-500">إدارة المصروفات والجرد والتسويات المالية</p></div>
        <div className="rounded-xl border border-gray-200 bg-white px-4 py-2 text-sm">المجموعة: مجموعتي　⌄</div>
      </header>
      <section className="mb-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {cards.map(c => <article key={c.title} className="rounded-2xl border border-gray-100 bg-white p-5 shadow-sm"><div className="mb-4 flex items-center justify-between"><span className="text-sm text-gray-500">{c.title}</span><span className="text-xl" style={{color:'var(--green)'}}>{c.icon}</span></div><div className="text-2xl font-bold">{c.value}</div><p className="mt-2 text-xs text-gray-400">{c.note}</p></article>)}
      </section>
      <div className="mb-8 flex justify-center"><button className="rounded-2xl px-10 py-5 text-xl font-bold text-white shadow-lg transition hover:brightness-110" style={{background:'var(--green)'}}>＋　إضافة مصروف</button></div>
      <section className="grid gap-5 lg:grid-cols-3">
        <article className="rounded-2xl border border-gray-100 bg-white p-6 lg:col-span-2"><h2 className="mb-4 text-lg font-bold">ملخص المصروفات</h2><div className="flex h-44 items-center justify-center rounded-xl bg-gray-50 text-sm text-gray-400">سيظهر الرسم البياني بعد تسجيل المصروفات</div></article>
        <article className="rounded-2xl border border-gray-100 bg-white p-6"><h2 className="mb-4 text-lg font-bold">آخر العمليات</h2><p className="rounded-xl bg-gray-50 p-5 text-center text-sm text-gray-400">لا توجد عمليات مسجلة بعد</p></article>
      </section>
      <nav className="mt-8 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {['المصروفات','الحسابات','التسويات','الجرد','التقارير','المجموعات','الملفات الشخصية','الإعدادات'].map(x=><div key={x} className="rounded-xl border border-gray-200 bg-white p-4 text-center text-sm font-semibold">{x}</div>)}
      </nav>
      <p className="mt-8 text-center text-xs text-gray-400">نسخة تأسيسية — البيانات المعروضة فارغة وليست بيانات مالية فعلية</p>
    </div>
  </main>;
}
