void qemu_ram_free(struct uc_struct *uc, RAMBlock *block)
{
    if (!block) {
        return;
    }
    QLIST_REMOVE(block, next);
    uc->ram_list.mru_block = NULL;
    reclaim_ramblock(uc, block);
}