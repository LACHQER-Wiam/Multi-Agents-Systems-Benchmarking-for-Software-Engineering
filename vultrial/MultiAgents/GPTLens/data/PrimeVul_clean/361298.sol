stl_update_connects_remove_1(stl_file *stl, int facet_num) {
  int j;
  if (
    stl->error ||
    facet_num < 0
  ) return;
  j = ((stl->neighbors_start[facet_num].neighbor[0] == -1) +
       (stl->neighbors_start[facet_num].neighbor[1] == -1) +
       (stl->neighbors_start[facet_num].neighbor[2] == -1));
  if(j == 0) {		       
    stl->stats.connected_facets_3_edge -= 1;
  } else if(j == 1) {	     
    stl->stats.connected_facets_2_edge -= 1;
  } else if(j == 2) {	     
    stl->stats.connected_facets_1_edge -= 1;
  }
}