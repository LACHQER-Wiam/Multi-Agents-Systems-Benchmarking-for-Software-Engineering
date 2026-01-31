ecc_256_modp (const struct ecc_modulo *p, mp_limb_t *rp)
{
  mp_limb_t u1, u0;
  mp_size_t n;
  n = 2*p->size;
  u1 = rp[--n];
  u0 = rp[n-1];
  for (; n >= p->size; n--)
    {
      mp_limb_t q2, q1, q0, t, cy;
      q1 = u1 - (u1 > u0);
      q0 = u0 - u1;
      t = u1 << 32;
      q0 += t;
      t = (u1 >> 32) + (q0 < t) + 1;
      q1 += t;
      q2 = q1 < t;
      u1 = u0 + (q1 << 32) - q1;
      t = -(mp_limb_t) (u1 > q0);
      u1 -= t & 0xffffffff;
      q1 += t;
      q2 += t + (q1 < t);
      assert (q2 < 2);
      t = mpn_submul_1 (rp + n - 4, p->m, 2, q1);
      t += cnd_sub_n (q2, rp + n - 3, p->m, 1);
      t += (-q2) & 0xffffffff;
      u0 = rp[n-2];
      cy = (u0 < t);
      u0 -= t;
      t = (u1 < cy);
      u1 -= cy;
      cy = cnd_add_n (t, rp + n - 4, p->m, 2);
      u0 += cy;
      u1 += (u0 < cy);
      u1 -= (-t) & 0xffffffff;
    }
  rp[2] = u0;
  rp[3] = u1;
}