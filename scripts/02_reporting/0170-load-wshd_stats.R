source('scripts/packages.R')
source('scripts/tables.R')

# retrieve the watersheds and elevations of the pscis sites then burn to the sqlite

# get phase 2 pscis site data from sqlite, only possible after provincial submission and bcfishpass db update
conn <- readwritesqlite::rws_connect("data/bcfishpass.sqlite")
readwritesqlite::rws_list_tables(conn)
bcfishpass_phase2 <- readwritesqlite::rws_read_table("bcfishpass", conn = conn) %>%
  filter(stream_crossing_id %in%
           (pscis_phase2 %>%
              pull(pscis_crossing_id))) %>%
  filter(!is.na(stream_crossing_id))

##we needed to remove crossings that are first order - this used to run but doesn't want to anymore
##i wonder if it is because the 1st order watershed is the first one on the list so the api kicks us off...
bcfishpass_phase2_clean <- bcfishpass_phase2 %>%
   filter(stream_order != 1)

# bcfishpass_phase2 %>%
#   filter(stream_order == 1)
# # see console - so far we don't have any first order watersheds so we don't need to do all the next moves!! If we do, we need to walk through it though
# conn <- DBI::dbConnect(
#   RPostgres::Postgres(),
#   dbname = Sys.getenv('PG_DB_SHARE'),
#   host = Sys.getenv('PG_HOST_SHARE'),
#   port = Sys.getenv('PG_PORT_SHARE'),
#   user = Sys.getenv('PG_USER_SHARE'),
#   password = Sys.getenv('PG_PASS_SHARE')
# )
#
# dat <- bcfishpass_phase2 %>%
#   filter(stream_order == 1)
#   # distinct(localcode_ltree, .keep_all = T)
# #
# # # add a unique id - we could just use the reference number
# dat$misc_point_id <- seq.int(nrow(dat))
#
# # ##pull out the localcode_ltrees we want
# ids <-  dat %>%
#   pull(localcode_ltree) %>%
#   # unique() %>%
#   as_vector() %>%
#   na.omit()
#
# ids2 <- dat %>%
#   pull(wscode_ltree) %>%
#   # unique() %>%
#   as_vector() %>%
#   na.omit()
# #
# # # note that we needed to specifiy the order here.  Not sure that is always going to save us....
# sql <- glue::glue_sql(
#
#                                 "SELECT localcode_ltree, wscode_ltree, area_ha, geom as geometry from whse_basemapping.fwa_watersheds_poly
#                                 WHERE localcode_ltree IN ({ids*})
#                                 AND wscode_ltree IN ({ids2*})
#                                 AND watershed_order = 1
#                                 ",
#   .con = conn
# )
#
# wshds_1ord_prep <- sf::st_read(conn,
#                         query = sql) %>%
#   st_transform(crs = 4326)
#
# # test <- wshds_1ord_prep %>%
# #   filter(localcode_ltree == wscode_ltree)
#
# # # i think we need to be joining in the stream_crossing_id and joining on that....
#
# wshds_1ord <- left_join(
#   dat %>%
#     distinct(stream_crossing_id, .keep_all = T) %>%
#     select(
#     stream_crossing_id,
#     localcode_ltree,
#     wscode_ltree,
#     stream_order
#     ) %>%
#     mutate(stream_crossing_id = as.character(stream_crossing_id)),
#     # filter(stream_order == 1),
#   wshds_1ord_prep %>%
#     mutate(localcode_ltree = as.character(localcode_ltree),
#            wscode_ltree = as.character(wscode_ltree)),
#   by = c('localcode_ltree','wscode_ltree')
# )


## call fwapgr - badass
wshds_fwapgr <- fpr::fpr_sp_watershed(bcfishpass_phase2_clean)

# join first order df to original df
# wshds <- bind_rows(
#   wshds_fwapgr,
#   wshds_1ord
# )

#so far we don't have any first order watersheds so
wshds <- wshds_fwapgr

## add in the elevation of the site
wshds <- left_join(wshds %>% mutate(stream_crossing_id = as.numeric(stream_crossing_id)),
                   pscis_all_sf %>% distinct(pscis_crossing_id, .keep_all = T) %>%
                     st_drop_geometry() %>%
                     select(pscis_crossing_id, elev_site = elev),
                   by = c('stream_crossing_id' = 'pscis_crossing_id'))

# calculate stats for each watershed
wshds <- fpr::fpr_sp_wshd_stats(dat = wshds) %>%
  mutate(area_km = round(area_ha/100, 1)) %>%
  mutate(across(contains('elev'), round, 0)) %>%
  arrange(stream_crossing_id)

# ##add to the geopackage - nned to mak
#wshds %>%
#  sf::st_write(paste0("./data/fishpass_mapping/", 'fishpass_mapping', ".gpkg"), 'hab_wshds',
#               delete_layer = T, append = F) ##might want to f the append....


#burn to kml as well so we can see elevations
st_write(wshds %>%
           rename(name = stream_crossing_id),
         append = F,
         delete_layer = T,
         driver = 'kml',
         dsn = "data/inputs_extracted/wshds.kml")


conn <- rws_connect("data/bcfishpass.sqlite")
rws_list_tables(conn)
rws_drop_table("wshds", conn = conn) ##now drop the table so you can replace it
rws_write(wshds, exists = F, delete = TRUE,
          conn = conn, x_name = "wshds")
rws_list_tables(conn)
rws_disconnect(conn)
